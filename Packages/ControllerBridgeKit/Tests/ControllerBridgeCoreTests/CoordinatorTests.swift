import Foundation
import ControllerBridgeCore
import Testing

/// A fake LC6000 plus a fake Syndicate, plugged into a Coordinator. Tests check only what comes out: the OSC sent
/// to Syndicate, the LED messages sent to the controller, and the log.
final class Rig {
    final class FakeOutput: MIDIOutput, @unchecked Sendable {
        struct SendFailed: Error {}
        var sent: [MIDIEvent] = []
        var closed = false
        /// Set to make every send fail, as a pulled cable can.
        var failing = false
        func send(_ event: MIDIEvent) throws {
            if failing { throw SendFailed() }
            sent.append(event)
        }
        func close() { closed = true }
    }

    final class FakeMIDISystem: MIDISystem, @unchecked Sendable {
        var sources: [MIDIEndpoint]
        var destinations: [MIDIEndpoint]
        var connected: [MIDIEndpoint.ID] = []
        var outputs: [MIDIEndpoint.ID: FakeOutput] = [:]

        init(sources: [MIDIEndpoint], destinations: [MIDIEndpoint]) {
            self.sources = sources
            self.destinations = destinations
        }

        func connect(source: MIDIEndpoint) throws { connected.append(source.id) }
        func disconnect(source: MIDIEndpoint) { connected.removeAll { $0 == source.id } }
        func openOutput(destination: MIDIEndpoint) throws -> any MIDIOutput {
            let output = FakeOutput()
            outputs[destination.id] = output
            return output
        }
    }

    final class FakeOSC: OSCSender, @unchecked Sendable {
        var sent: [OSCMessage] = []
        func send(_ message: OSCMessage) { sent.append(message) }
    }

    final class FakeClock: Clock, @unchecked Sendable {
        var now: Double = 0
    }

    final class FakeLog: LogSink, @unchecked Sendable {
        var lines: [String] = []
        func log(_ line: String) { lines.append(line) }
    }

    static let lc6000 = MIDIEndpoint(id: 1001, name: "DENON LC6000 PRIME")
    static let lc6000Out = MIDIEndpoint(id: 2001, name: "DENON LC6000 PRIME")

    let midi = FakeMIDISystem(sources: [MIDIEndpoint(id: 1000, name: "IAC Bus 1"), Rig.lc6000], destinations: [Rig.lc6000Out])
    let osc = FakeOSC()
    let clock = FakeClock()
    let log = FakeLog()
    let coordinator: Coordinator

    /// The latest velocity sent to each LED note on the controller's output.
    var leds: [UInt8: UInt8] {
        var out: [UInt8: UInt8] = [:]
        for case let .noteOn(_, note, velocity) in midi.outputs[Rig.lc6000Out.id]?.sent ?? [] { out[note] = velocity }
        return out
    }

    /// A rig whose mapping is the default with `override` (a JSON mapping file) merged over it.
    init(override: String? = nil) throws {
        let mapping = try override.map { try Mapping.bundledDefault(overriddenBy: Data($0.utf8)) } ?? Mapping.bundledDefault()
        coordinator = Coordinator(mapping: mapping, midi: midi, osc: osc, clock: clock, log: log)
    }
}

@Suite("Coordinator")
struct CoordinatorTests {
    @Test("Start asks Syndicate to resend its state")
    func startAsksForResend() throws {
        let rig = try Rig()
        rig.coordinator.start()
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])])
    }

    @Test("Start connects the source whose name matches the mapping's input, and no other")
    func startConnectsController() throws {
        let rig = try Rig()
        rig.coordinator.start()
        #expect(rig.midi.connected == [Rig.lc6000.id])
    }

    @Test("Pressing Play sends PlayPause 1; releasing it (note off, or note on at velocity 0) sends nothing")
    func playIsATrigger() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()

        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOff(channel: 0, note: 1, velocity: 0), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 0), source: Rig.lc6000.id)

        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
    }

    @Test("The Play LED is dim (1) while stopped and full (127) while Syndicate reports Playing")
    func playLEDFollowsPlaying() throws {
        let rig = try Rig()
        rig.coordinator.start()
        #expect(rig.leds[1] == 1)

        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        #expect(rig.leds[1] == 127)

        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)]))
        #expect(rig.leds[1] == 1)
    }

    @Test("Feedback addresses match without regard to case")
    func feedbackIgnoresCase() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/syndicate/deck/1/playing", [.int(1)]))
        #expect(rig.leds[1] == 127)
    }

    @Test("Feedback for another deck leaves this controller's LEDs alone")
    func feedbackForOtherDeck() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        #expect(rig.leds[1] == 1)
    }

    @Test("MIDI on another channel is ignored")
    func otherChannelIgnored() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        rig.coordinator.midi(.noteOn(channel: 1, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent == [])
    }

    @Test("An unchanged LED isn't sent twice: repeated Playing 1 lights the Play LED once")
    func unchangedLEDNotResent() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        let playOn = rig.midi.outputs[Rig.lc6000Out.id]?.sent.filter { $0 == .noteOn(channel: 0, note: 1, velocity: 127) }
        #expect(playOn?.count == 1)
    }
}
