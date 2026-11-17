// Drives the LC6000 jog display (#165): the hello, then one image upload at a time, into slot 1 and 2 by turns so the
// shown image stays up while the next one loads, the newest content winning; a refusal or a silent unit is logged
// once and not retried until the content changes; goodbye at the end.

/// Where the jog display's messages go: the Controller port (the hello and goodbye) and the WD port (images, the
/// marker). The app's CoreMIDI adapter, a test's fake, and the Diagnostics simulator (#221) all take this.
public protocol JogDisplayPort: AnyObject, Sendable {
    func sendController(_ bytes: [UInt8])
    func sendWD(_ bytes: [UInt8])
    /// Whether the unit's WD port is there now (#305). Without it there's no display to say hello to.
    var isAttached: Bool { get }
}

extension JogDisplayPort {
    public var isAttached: Bool { true }
}

/// What the display shows for the deck in front (#165). Two of these that are equal draw the same image.
public struct JogDisplayContent: Equatable, Sendable {
    public var deck: Int
    /// The deck's color, [r, g, b].
    public var color: [Int]
    /// From Syndicate's TrackInfo: nil until a track is loaded.
    public var title: String?
    public var artist: String?
    public var key: String?
    public var bpm: Double?
    /// "track", "empty", or what a clip or sequencer says (#209).
    public var playerType: String?

    public init(deck: Int, color: [Int], title: String? = nil, artist: String? = nil, key: String? = nil, bpm: Double? = nil,
                playerType: String? = nil) {
        self.deck = deck
        self.color = color
        self.title = title
        self.artist = artist
        self.key = key
        self.bpm = bpm
        self.playerType = playerType
    }
}

/// What the driver did, for the Diagnostics simulator (#221): the same facts as the bytes it sent.
public enum JogDisplayEvent: Equatable, Sendable {
    case connected
    case disconnected
    /// An image for `content` started into `slot`: `bytes` of SysEx on the wire.
    case uploadStarted(slot: UInt8, content: JogDisplayContent, bytes: Int)
    /// The unit stored it and shows `slot` now.
    case shown(slot: UInt8)
    /// The upload stopped: refused with the ack's status, or nil for no answer.
    case failed(refusal: UInt8?)
    /// The needle on the unit: the deck in front's (pitch bend on WD).
    case marker(pitchBend: Int)
    case playLight(Bool)
    /// Each deck's needle for the simulator (#165): its own phase in the bar. Nothing is sent for it.
    case deckMarker(deck: Int, pitchBend: Int)
    /// The master clock's beat (1-4), the lit ring segment on every deck. Nothing is sent for it (#215 may draw it).
    case masterBeat(Int)
    /// Whether `deck` is playing, from Syndicate's feedback, reported on change (#317). Nothing is sent for it: the
    /// unit's play light is `playLight`, which also blinks while a loaded deck is paused.
    case deckPlaying(deck: Int, playing: Bool)
    /// What a deck's display would show (#221): every deck, live, for the simulator; only the deck in front is
    /// uploaded. Nothing is sent for it.
    case preview(JogDisplayContent)
}

public final class JogDisplayDriver {
    /// Called with each thing the driver does (#221).
    public var onEvent: ((JogDisplayEvent) -> Void)?

    /// The unit's ports; nil when there's no LC6000 jog display, and the driver only previews (#221).
    private let port: (any JogDisplayPort)?
    private let clock: any Clock
    private let log: any LogSink
    /// The image's width and height: 198 on the unit.
    private let size: Int
    /// Draws content as RGBA rows, upright; the driver turns and encodes it.
    private let render: (JogDisplayContent) -> [UInt8]

    /// How long an upload may wait for the unit's answers.
    static let timeout = 5.0

    private var connected = false
    /// Whether the hello went out and no goodbye since.
    public var isConnected: Bool { connected }
    /// The last marker and play light sent, so only changes go out.
    private var lastMarker: Int?
    private var lastPlayLight: Bool?
    /// The content shown, or being uploaded, and the content wanted next.
    private var current: JogDisplayContent?
    private var wanted: JogDisplayContent?
    /// The slot shown; the next upload goes into the other one.
    private var shownSlot: UInt8 = 2
    /// The last content drawn and its image (#221): what the preview drew goes to the unit when it connects, unredrawn.
    /// Each deck's last previewed content.
    private var previews: [Int: JogDisplayContent] = [:]
    private var deckMarkers: [Int: Int] = [:]
    private var lastMasterBeat: Int?
    private var deckPlays: [Int: Bool] = [:]
    private var drawn: (content: JogDisplayContent, image: [UInt8])?
    private var upload: (upload: JogDisplay.Upload, slot: UInt8, acks: Int, finished: Bool, startedAt: Double)?

    public init(port: (any JogDisplayPort)?, clock: any Clock, log: any LogSink, size: Int = JogImage.size,
                render: @escaping (JogDisplayContent) -> [UInt8]) {
        self.port = port
        self.clock = clock
        self.log = log
        self.size = size
        self.render = render
    }

    /// Whether a unit's WD port is there to show on (#305).
    public var attached: Bool { port?.isAttached == true }

    /// The unit is attached: say hello as a host, then show what's wanted. With no port it stays a preview.
    public func connect() {
        guard !connected, let port else { return }
        connected = true
        // What the preview showed goes to the unit now, and the marker and light are sent afresh.
        if wanted == nil { wanted = current }
        current = nil
        lastMarker = nil
        lastPlayLight = nil
        for message in JogDisplay.hello { port.sendController(message) }
        onEvent?(.connected)
        next()
    }

    /// The unit is going away, or the app is quitting: goodbye, so it returns to standalone.
    public func disconnect() {
        guard connected else { return }
        connected = false
        upload = nil
        lastMarker = nil
        lastPlayLight = nil
        current = nil
        port?.sendController(JogDisplay.goodbye)
        onEvent?(.disconnected)
    }

    /// Asks for `content` on the display. Equal content sends nothing; while an upload runs, only the newest waits.
    public func show(_ content: JogDisplayContent) {
        wanted = content
        if upload == nil { next() }
    }

    /// The marker at `pitchBend` (0...16383): pitch bend on WD ch1. Only a change goes out.
    public func marker(_ pitchBend: Int) {
        guard pitchBend != lastMarker else { return }
        lastMarker = pitchBend
        if connected { port?.sendWD([0xE0, UInt8(pitchBend & 0x7F), UInt8(pitchBend >> 7 & 0x7F)]) }
        onEvent?(.marker(pitchBend: pitchBend))
    }

    /// A deck's needle for the simulator, reported on change; nothing is sent to the unit.
    public func deckMarker(deck: Int, _ pitchBend: Int) {
        guard deckMarkers[deck] != pitchBend else { return }
        deckMarkers[deck] = pitchBend
        onEvent?(.deckMarker(deck: deck, pitchBend: pitchBend))
    }

    /// The master clock's beat, reported on change; nothing is sent to the unit.
    public func masterBeat(_ beat: Int) {
        guard beat != lastMasterBeat else { return }
        lastMasterBeat = beat
        onEvent?(.masterBeat(beat))
    }

    /// A deck's play state, reported on change; nothing is sent to the unit.
    public func deckPlaying(deck: Int, _ playing: Bool) {
        guard deckPlays[deck] != playing else { return }
        deckPlays[deck] = playing
        onEvent?(.deckPlaying(deck: deck, playing: playing))
    }

    /// The play light: note 1 on WD ch1, 127 or 0. Only a change goes out.
    public func playLight(_ on: Bool) {
        guard on != lastPlayLight else { return }
        lastPlayLight = on
        if connected { port?.sendWD([0x90, 0x01, on ? 0x7F : 0x00]) }
        onEvent?(.playLight(on))
    }

    /// A deck's content for the simulator (#221), reported on change; nothing is sent to the unit.
    public func preview(_ content: JogDisplayContent) {
        guard previews[content.deck] != content else { return }
        previews[content.deck] = content
        onEvent?(.preview(content))
    }

    /// A message from the WD port.
    public func reply(_ bytes: [UInt8]) {
        guard var running = upload, let reply = JogDisplay.Reply(bytes) else { return }
        switch reply {
        case .accepted where !running.finished:
            running.acks += 1
            if running.acks == running.upload.expectedAcks {
                running.finished = true
                for message in running.upload.finish { port?.sendWD(message) }
            }
            upload = running
        case .refused(let status):
            log.log("The jog display refused the image (ack \(String(format: "%02X", status))); it keeps what it showed")
            fail()
            onEvent?(.failed(refusal: status))
        case .committed where running.finished:
            port?.sendWD(running.upload.show)
            shownSlot = running.slot
            onEvent?(.shown(slot: running.slot))
            upload = nil
            next()
        default:
            break
        }
    }

    /// Times out a silent upload; starts the next one.
    public func tick() {
        if let running = upload, clock.now - running.startedAt >= Self.timeout {
            log.log("The jog display didn't answer the upload; it keeps what it showed")
            fail()
            onEvent?(.failed(refusal: nil))
        }
        if upload == nil { next() }
    }

    /// The upload is over without a show: what's shown stays, and nothing retries until the content changes.
    private func fail() {
        upload = nil
        wanted = nil
    }

    private func next() {
        guard upload == nil, let content = wanted, content != current else { return }
        wanted = nil
        current = content
        let slot: UInt8 = shownSlot == 1 ? 2 : 1
        let image: [UInt8]
        if let drawn, drawn.content == content {
            image = drawn.image
        } else {
            image = JogImage.forUnit(rgba: render(content), width: size, height: size)
            drawn = (content, image)
        }
        let job = JogDisplay.Upload(image: image, slot: slot)
        // A preview (#221): no unit, so nothing is sent and nothing waits for an answer; it's shown at once.
        guard connected, let port else {
            shownSlot = slot
            onEvent?(.uploadStarted(slot: slot, content: content, bytes: job.body.reduce(0) { $0 + $1.count }))
            onEvent?(.shown(slot: slot))
            return
        }
        upload = (job, slot, 0, false, clock.now)
        for message in job.start + job.body { port.sendWD(message) }
        onEvent?(.uploadStarted(slot: slot, content: content, bytes: job.body.reduce(0) { $0 + $1.count }))
        // The upload's start turns the play light off (90 01 00): the next tick puts it back.
        lastPlayLight = false
    }
}
