/// Runs the Bridges (one per controller) against the MIDI system, the OSC sender, a clock and a log.
///
/// Not thread-safe on purpose: the app confines it to one serial consumer that feeds it MIDI, feedback and ticks in
/// order. Tests call it directly.
public final class Coordinator {
    private let midiSystem: any MIDISystem
    private let osc: any OSCSender
    private let clock: any Clock
    private let log: any LogSink
    private var controllers: [Controller]
    private var bridges: [Bridge] { controllers.map(\.bridge) }

    /// What the menu shows. The app copies it after each call.
    public private(set) var status: CoordinatorStatus

    /// A Bridge and the devices it is connected to.
    private struct Controller {
        let bridge: Bridge
        var source: MIDIEndpoint?
        /// The unique id of the last source this controller used, so a replug finds the same unit first.
        var knownSourceID: MIDIEndpoint.ID?
    }

    public init(mapping: Mapping, midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        self.midiSystem = midi
        self.osc = osc
        self.clock = clock
        self.log = log
        controllers = [Controller(bridge: Bridge(mapping: mapping, osc: osc, clock: clock))]
        status = CoordinatorStatus(controllers: [ControllerStatus(deck: mapping.deck.number, connected: false)])
    }

    /// Opens each controller's ports, asks Syndicate for its state and paints the LEDs. Starting with no controller
    /// connected is not an error: it connects when it appears.
    public func start() {
        for index in controllers.indices {
            if !connect(index) {
                log.log("No controller matching \"\(controllers[index].bridge.mapping.midi.input)\" yet")
            }
            controllers[index].bridge.start()
        }
    }

    /// The MIDI devices changed. Re-reads them, connecting controllers that appeared.
    public func devicesChanged() {
        for index in controllers.indices {
            if let source = controllers[index].source {
                if !midiSystem.sources.contains(where: { $0.id == source.id }) { disconnect(index) }
            } else if connect(index) {
                controllers[index].bridge.start()
            }
        }
        disconnectFailedOutputs()
    }

    /// Releases everything the controller held, exactly once, and closes its ports.
    private func disconnect(_ index: Int, reason: String? = nil) {
        guard let source = controllers[index].source else { return }
        let bridge = controllers[index].bridge
        bridge.releaseAll()
        midiSystem.disconnect(source: source)
        bridge.output?.close()
        bridge.output = nil
        controllers[index].source = nil
        report(index, "Disconnected \(source.name)" + (reason.map { " (\($0))" } ?? ""))
    }

    /// Opens the controller's ports if a matching device is present. Returns whether its input is connected.
    private func connect(_ index: Int) -> Bool {
        let bridge = controllers[index].bridge
        let sources = midiSystem.sources
        let known = controllers[index].knownSourceID.flatMap { id in sources.first { $0.id == id } }
        guard let source = known ?? Self.match(sources, bridge.mapping.midi.input) else { return false }
        do {
            try midiSystem.connect(source: source)
        } catch {
            log.log("Couldn't open MIDI input \(source.name): \(error)")
            return false
        }
        controllers[index].source = source
        controllers[index].knownSourceID = source.id
        if let destination = Self.match(midiSystem.destinations, bridge.mapping.midi.output) {
            do { bridge.output = try midiSystem.openOutput(destination: destination) } catch {
                log.log("Couldn't open MIDI output \(destination.name): \(error)")
            }
        }
        report(index, "Connected \(source.name)")
        return true
    }

    private func report(_ index: Int, _ event: String) {
        log.log(event)
        status.controllers[index].connected = controllers[index].source != nil
        status.controllers[index].lastEvent = event
    }

    /// Releases everything held in Syndicate. Safe to call again: a second call sends nothing.
    public func stop() {
        for bridge in bridges { bridge.releaseAll() }
    }

    /// Runs timers, such as releasing a jog nudge after the wheel stops. The app calls it about every 10 ms.
    public func tick() {
        for bridge in bridges { bridge.tick() }
        disconnectFailedOutputs()
    }

    /// The first endpoint whose name contains `wanted`, ignoring case.
    private static func match(_ endpoints: [MIDIEndpoint], _ wanted: String) -> MIDIEndpoint? {
        endpoints.first { $0.name.lowercased().contains(wanted.lowercased()) }
    }

    /// A MIDI message from a source. Only the controller connected to that source handles it.
    public func midi(_ event: MIDIEvent, source: MIDIEndpoint.ID) {
        for controller in controllers where controller.source?.id == source { controller.bridge.handle(event) }
        disconnectFailedOutputs()
    }

    /// An OSC feedback message from Syndicate. One listener fans out to every Bridge.
    public func feedback(_ message: OSCMessage) {
        for bridge in bridges { bridge.handle(message) }
        disconnectFailedOutputs()
    }

    /// A failed MIDI send means the controller is gone, even before CoreMIDI says so.
    private func disconnectFailedOutputs() {
        for index in controllers.indices where controllers[index].bridge.outputFailed {
            disconnect(index, reason: "MIDI send failed")
        }
    }
}
