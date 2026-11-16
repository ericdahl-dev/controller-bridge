// Drives the LC6000 jog display (#165): the hello, then one image upload at a time, into slot 1 and 2 by turns so the
// shown image stays up while the next one loads, the newest content winning; a refusal or a silent unit is logged
// once and not retried until the content changes; goodbye at the end.

/// Where the jog display's messages go: the Controller port (the hello and goodbye) and the WD port (images, the
/// marker). The app's CoreMIDI adapter, a test's fake, and the Diagnostics simulator (#221) all take this.
public protocol JogDisplayPort: AnyObject, Sendable {
    func sendController(_ bytes: [UInt8])
    func sendWD(_ bytes: [UInt8])
}

/// What the display shows for the deck in front (#165). Two of these that are equal draw the same image.
public struct JogDisplayContent: Equatable, Sendable {
    public var deck: Int
    /// The deck's color, [r, g, b].
    public var color: [Int]

    public init(deck: Int, color: [Int]) {
        self.deck = deck
        self.color = color
    }
}

public final class JogDisplayDriver {
    private let port: any JogDisplayPort
    private let clock: any Clock
    private let log: any LogSink
    /// The image's width and height: 198 on the unit.
    private let size: Int
    /// Draws content as RGBA rows, upright; the driver turns and encodes it.
    private let render: (JogDisplayContent) -> [UInt8]

    /// How long an upload may wait for the unit's answers.
    static let timeout = 5.0

    private var connected = false
    /// The content shown, or being uploaded, and the content wanted next.
    private var current: JogDisplayContent?
    private var wanted: JogDisplayContent?
    /// The slot shown; the next upload goes into the other one.
    private var shownSlot: UInt8 = 2
    private var upload: (upload: JogDisplay.Upload, slot: UInt8, acks: Int, finished: Bool, startedAt: Double)?

    public init(port: any JogDisplayPort, clock: any Clock, log: any LogSink, size: Int = JogImage.size,
                render: @escaping (JogDisplayContent) -> [UInt8]) {
        self.port = port
        self.clock = clock
        self.log = log
        self.size = size
        self.render = render
    }

    /// The unit is attached: say hello as a host, then show what's wanted.
    public func connect() {
        guard !connected else { return }
        connected = true
        for message in JogDisplay.hello { port.sendController(message) }
        next()
    }

    /// The unit is going away, or the app is quitting: goodbye, so it returns to standalone.
    public func disconnect() {
        guard connected else { return }
        connected = false
        upload = nil
        current = nil
        port.sendController(JogDisplay.goodbye)
    }

    /// Asks for `content` on the display. Equal content sends nothing; while an upload runs, only the newest waits.
    public func show(_ content: JogDisplayContent) {
        wanted = content
        if upload == nil { next() }
    }

    /// A message from the WD port.
    public func reply(_ bytes: [UInt8]) {
        guard var running = upload, let reply = JogDisplay.Reply(bytes) else { return }
        switch reply {
        case .accepted where !running.finished:
            running.acks += 1
            if running.acks == running.upload.expectedAcks {
                running.finished = true
                for message in running.upload.finish { port.sendWD(message) }
            }
            upload = running
        case .refused(let status):
            log.log("The jog display refused the image (ack \(String(format: "%02X", status))); it keeps what it showed")
            fail()
        case .committed where running.finished:
            port.sendWD(running.upload.show)
            shownSlot = running.slot
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
        }
        if upload == nil { next() }
    }

    /// The upload is over without a show: what's shown stays, and nothing retries until the content changes.
    private func fail() {
        upload = nil
        wanted = nil
    }

    private func next() {
        guard connected, upload == nil, let content = wanted, content != current else { return }
        wanted = nil
        current = content
        let slot: UInt8 = shownSlot == 1 ? 2 : 1
        let image = JogImage.forUnit(rgba: render(content), width: size, height: size)
        let job = JogDisplay.Upload(image: image, slot: slot)
        upload = (job, slot, 0, false, clock.now)
        for message in job.start + job.body { port.sendWD(message) }
    }
}
