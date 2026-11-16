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
