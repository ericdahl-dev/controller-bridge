// The built-in demo controller (#64), for App Review: no DJ controller, no Syndicate. A real Coordinator runs the
// active profile against an in-process demo controller and an in-memory Syndicate, so the panel shows CONNECTED and
// LIVE and the Diagnostics window fills with traffic. Nothing is sent to the network.

/// A demo run: its own Coordinator, a scripted controller and a Syndicate that answers in memory.
public final class DemoSession {
    public let coordinator: Coordinator
    private let clock: any Clock
    private let syndicate: DemoSyndicate
    private let source: MIDIEndpoint
    private let script: [DemoScript.Step]
    private var startedAt = 0.0
    private var cycle = 0
    private var nextStep = 0
    private var nextBeat = 0.0
    private var beat: Int32 = 0
    private var running = false

    /// The name the demo controller shows under, and matches its profile by.
    public static let deviceName = "Demo controller"

    /// `ledOutput` receives the demo controller's LED writes (the app drops them; tests read them).
    public init(profile: ControllerProfile, clock: any Clock, log: any LogSink, ledOutput: any MIDIOutput) {
        var demo = profile
        demo.deviceHints = [Self.deviceName]
        demo.mapping.midi.input = Self.deviceName
        demo.mapping.midi.output = Self.deviceName
        source = MIDIEndpoint(id: -64, name: Self.deviceName)
        let destination = MIDIEndpoint(id: -65, name: Self.deviceName)
        syndicate = DemoSyndicate(mapping: demo.mapping)
        script = DemoScript.steps(for: demo.mapping)
        self.clock = clock
        coordinator = Coordinator(
            profiles: [demo],
            midi: DemoMIDISystem(source: source, destination: destination, output: ledOutput),
            osc: syndicate, clock: clock, log: log
        )
    }

    /// Everything the bridge sent to the in-memory Syndicate, in order.
    public var sentToSyndicate: [OSCMessage] { syndicate.received }

    /// The demo Coordinator's status, marked as the demo.
    public var status: CoordinatorStatus {
        var status = coordinator.status
        status.demo = true
        return status
    }

    public func start() {
        running = true
        startedAt = clock.now
        nextBeat = clock.now
        coordinator.start()
        deliverReplies()
    }

    /// Runs the script's due steps, the Coordinator's timers and Syndicate's answers. The app calls it every 10 ms.
    public func tick() {
        guard running else { return }
        let now = clock.now
        while now + 1e-9 >= startedAt + Double(cycle) * DemoScript.period + script[nextStep].at {
            coordinator.midi(script[nextStep].event, source: source.id)
            nextStep += 1
            if nextStep == script.count { nextStep = 0; cycle += 1 }
        }
        // Syndicate's master clock, 120 BPM, while the demo deck plays.
        if syndicate.playing, now + 1e-9 >= nextBeat {
            beat = beat % 4 + 1
            syndicate.queue(OSCMessage(syndicate.root + "Header/Clock", [.int(beat)]))
            nextBeat = now + 0.5
        }
        coordinator.tick()
        deliverReplies()
    }

    /// Ends the demo: what it holds is released (to the in-memory Syndicate), and nothing more runs.
    public func stop() {
        guard running else { return }
        running = false
        coordinator.stop()
    }

    private func deliverReplies() {
        for reply in syndicate.takeReplies() { coordinator.feedback(reply) }
    }
}

/// What the demo controller does, as data: Play, a pitch fader move from center, a jog nudge, then Play again to stop.
/// Built from the profile's mapping, and repeated every `period` seconds.
enum DemoScript {
    struct Step {
        var at: Double
        var event: MIDIEvent
    }

    static let period = 8.0

    static func steps(for mapping: Mapping) -> [Step] {
        let channel = UInt8(clamping: mapping.midi.channel - 1)
        let play = UInt8(clamping: mapping.notes.buttons["play"] ?? 0)
        let pitch = UInt8(clamping: mapping.pitch.msbCC)
        let (jogMSB, jogLSB) = (UInt8(clamping: mapping.jog.msbCC), UInt8(clamping: mapping.jog.lsbCC))
        var steps = [
            Step(at: 0.5, event: .noteOn(channel: channel, note: play, velocity: 127)),
            Step(at: 0.6, event: .noteOff(channel: channel, note: play, velocity: 0)),
        ]
        // The pitch fader from center (0x40) up a quarter (0x50), in five moves.
        for (index, msb) in [UInt8(0x40), 0x44, 0x48, 0x4C, 0x50].enumerated() {
            steps.append(Step(at: 1.0 + Double(index) * 0.25, event: .controlChange(channel: channel, controller: pitch, value: msb)))
        }
        // The jog, the platter position counting up 8 at a time as a slow forward turn does (#103): a nudge while
        // playing. The first position is only the starting point.
        for (index, position) in stride(from: 100, through: 140, by: 8).enumerated() {
            let at = 3.0 + Double(index) * 0.05
            steps.append(Step(at: at, event: .controlChange(channel: channel, controller: jogMSB, value: UInt8(position >> 7))))
            steps.append(Step(at: at, event: .controlChange(channel: channel, controller: jogLSB, value: UInt8(position & 0x7F))))
        }
        steps += [
            Step(at: 6.0, event: .noteOn(channel: channel, note: play, velocity: 127)),
            Step(at: 6.1, event: .noteOff(channel: channel, note: play, velocity: 0)),
        ]
        return steps
    }
}

/// Syndicate in memory: it records what it is sent and queues the answers a real one would send back.
final class DemoSyndicate: OSCSender, @unchecked Sendable {
    let root: String
    private let deck: String
    private(set) var received: [OSCMessage] = []
    private var replies: [OSCMessage] = []
    private(set) var playing = false
    private var tempo: Float = 0

    init(mapping: Mapping) {
        root = "/" + mapping.osc.root.split(separator: "/").joined(separator: "/") + "/"
        deck = root + "Deck/\(mapping.deck.number)/"
    }

    func send(_ message: OSCMessage) {
        received.append(message)
        switch message.address.lowercased() {
        case (root + "Feedback/Resend").lowercased():
            replies += [
                OSCMessage(deck + "Loaded", [.int(1)]),
                OSCMessage(deck + "Playing", [.int(playing ? 1 : 0)]),
                OSCMessage(deck + "TempoSliderEnabled", [.int(1)]),
                OSCMessage(deck + "TempoSlider", [.float(tempo)]),
                OSCMessage(deck + "Cues", [.int(1), .string("Intro"), .int(2), .string("Drop")]
                    + Array(repeating: [OSCArgument.int(0), .string("")], count: 6).flatMap { $0 }),
            ]
        case (deck + "PlayPause").lowercased():
            playing.toggle()
            replies.append(OSCMessage(deck + "Playing", [.int(playing ? 1 : 0)]))
        case (deck + "TempoSlider").lowercased():
            if case .float(let value) = message.arguments.first { tempo = value }
            replies.append(OSCMessage(deck + "TempoSlider", [.float(tempo)]))
        default:
            break
        }
    }

    func queue(_ message: OSCMessage) { replies.append(message) }

    func takeReplies() -> [OSCMessage] {
        defer { replies.removeAll() }
        return replies
    }
}

/// One in-process controller: a MIDI source the script plays, and a destination whose LED writes go to `output`.
final class DemoMIDISystem: MIDISystem, @unchecked Sendable {
    let sources: [MIDIEndpoint]
    let destinations: [MIDIEndpoint]
    private let output: any MIDIOutput

    init(source: MIDIEndpoint, destination: MIDIEndpoint, output: any MIDIOutput) {
        sources = [source]
        destinations = [destination]
        self.output = output
    }

    func connect(source: MIDIEndpoint) throws {}
    func disconnect(source: MIDIEndpoint) {}
    func openOutput(destination: MIDIEndpoint) throws -> any MIDIOutput { output }
}
