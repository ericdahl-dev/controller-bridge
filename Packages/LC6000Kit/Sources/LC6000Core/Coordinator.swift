/// Runs the Bridges (one per controller) against the MIDI system, the OSC sender, a clock and a log.
///
/// Not thread-safe on purpose: the app confines it to one serial consumer that feeds it MIDI, feedback and ticks in
/// order. Tests call it directly.
public final class Coordinator {
    private let midiSystem: any MIDISystem
    private let osc: any OSCSender
    private let clock: any Clock
    private let log: any LogSink
    private var bridges: [Bridge]

    public init(mapping: Mapping, midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        self.midiSystem = midi
        self.osc = osc
        self.clock = clock
        self.log = log
        bridges = [Bridge(mapping: mapping, osc: osc)]
    }

    /// Opens each controller's ports, asks Syndicate for its state and paints the LEDs. Starting with no controller
    /// connected is not an error.
    public func start() {
        for bridge in bridges {
            if let source = Self.match(midiSystem.sources, bridge.mapping.midi.input) {
                do { try midiSystem.connect(source: source) } catch { log.log("Couldn't open MIDI input \(source.name): \(error)") }
            }
            if let destination = Self.match(midiSystem.destinations, bridge.mapping.midi.output) {
                do { bridge.output = try midiSystem.openOutput(destination: destination) } catch {
                    log.log("Couldn't open MIDI output \(destination.name): \(error)")
                }
            }
            bridge.start()
        }
    }

    /// The first endpoint whose name contains `wanted`, ignoring case.
    private static func match(_ endpoints: [MIDIEndpoint], _ wanted: String) -> MIDIEndpoint? {
        endpoints.first { $0.name.lowercased().contains(wanted.lowercased()) }
    }

    /// A MIDI message from a connected source.
    public func midi(_ event: MIDIEvent, source: MIDIEndpoint.ID) {
        for bridge in bridges { bridge.handle(event) }
    }

    /// An OSC feedback message from Syndicate. One listener fans out to every Bridge.
    public func feedback(_ message: OSCMessage) {
        for bridge in bridges { bridge.handle(message) }
    }
}

/// One controller's translation: its MIDI in to Syndicate OSC, and Syndicate feedback to its LEDs.
final class Bridge {
    static let full: UInt8 = 127
    static let dim: UInt8 = 1
    static let off: UInt8 = 0

    let mapping: Mapping
    var output: (any MIDIOutput)?
    private let osc: any OSCSender
    private let root: String
    private let channel: UInt8

    // Syndicate's state, from feedback.
    private var playing = false

    /// The last velocity sent to each LED note, so an unchanged LED is never sent twice.
    private var ledCache: [Int: UInt8] = [:]

    init(mapping: Mapping, osc: any OSCSender) {
        self.mapping = mapping
        self.osc = osc
        root = "/" + mapping.osc.root.trimmingSlashes() + "/"
        channel = UInt8(mapping.midi.channel - 1)
    }

    func start() {
        send("Feedback/Resend", .int(1))
        ledCache.removeAll()
        refreshLEDs()
    }

    // MARK: MIDI in

    func handle(_ event: MIDIEvent) {
        switch event {
        case .noteOn(_, let note, let velocity): handleNote(Int(note), pressed: velocity > 0)
        case .noteOff(_, let note, _): handleNote(Int(note), pressed: false)
        case .controlChange: break
        }
    }

    private func handleNote(_ note: Int, pressed: Bool) {
        // Triggers fire on press only.
        if note == mapping.notes.buttons["play"], pressed { sendDeck("PlayPause", .int(1)) }
    }

    // MARK: Feedback in

    func handle(_ message: OSCMessage) {
        // Syndicate matches addresses without regard to case, so feedback is read the same way.
        let address = message.address.lowercased()
        let deckPrefix = (root + "Deck/\(mapping.deck.number)/").lowercased()
        guard address.hasPrefix(deckPrefix) else { return }
        let key = address.dropFirst(deckPrefix.count)
        let value = message.arguments.first?.isTrue ?? false
        switch key {
        case "playing": playing = value
        default: return
        }
        refreshLEDs()
    }

    // MARK: LEDs

    private func refreshLEDs() {
        buttonLED("play", on: playing)
    }

    private func buttonLED(_ name: String, on: Bool) {
        guard let note = mapping.notes.buttons[name] else { return }
        let idle = mapping.leds.dimUnlitButtons ? Self.dim : Self.off
        led(note, on ? Self.full : idle)
    }

    private func led(_ note: Int, _ velocity: UInt8) {
        guard ledCache[note] != velocity else { return }
        ledCache[note] = velocity
        output?.send(.noteOn(channel: channel, note: UInt8(note), velocity: velocity))
    }

    // MARK: OSC out

    private func sendDeck(_ path: String, _ arguments: OSCArgument...) {
        osc.send(OSCMessage(root + "Deck/\(mapping.deck.number)/" + path, arguments))
    }

    private func send(_ path: String, _ arguments: OSCArgument...) {
        osc.send(OSCMessage(root + path, arguments))
    }
}

private extension OSCArgument {
    /// Feedback flags arrive as an int or a float; anything nonzero is on.
    var isTrue: Bool {
        switch self {
        case .int(let value): value != 0
        case .float(let value): value != 0
        case .string: false
        }
    }
}

private extension String {
    func trimmingSlashes() -> String {
        String(drop { $0 == "/" }.reversed().drop { $0 == "/" }.reversed())
    }
}
