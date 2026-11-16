import ControllerBridgeCore
import Foundation
import Testing

/// Diagnostics (#26): the MIDI monitor, the OSC log and the LED sweep, replacing the Python `monitor` and `led-sweep`
/// commands. Expected text is copied from what lc6000_bridge/cli.py prints, so hardware checks read the same.
@Suite("Diagnostics")
struct DiagnosticsTests {
    final class Events {
        var all: [DiagnosticEvent] = []
        var monitor: [String] { all.compactMap { if case .midiIn = $0 { $0.text } else { nil } } }
        var osc: [String] { all.compactMap { switch $0 { case .oscOut, .oscIn: $0.text; default: nil } } }
        var sweep: [String] { all.compactMap { if case .sweep = $0 { $0.text } else { nil } } }
    }

    /// A started rig whose diagnostics are open (a sink is set).
    static func openRig() throws -> (Rig, Events) {
        let rig = try Rig()
        rig.coordinator.start()
        let events = Events()
        rig.coordinator.diagnostics = { events.all.append($0) }
        return (rig, events)
    }

    @Test("The monitor names each message from the mapping, or UNMAPPED, in the Python monitor's columns")
    func monitorNames() throws {
        let (rig, events) = try Self.openRig()
        rig.clock.now = 12.3456
        for event: MIDIEvent in [
            .noteOn(channel: 0, note: 1, velocity: 127),
            .noteOff(channel: 0, note: 1, velocity: 0),
            .noteOn(channel: 0, note: 32, velocity: 127),
            .controlChange(channel: 0, controller: 55, value: 1),
            .controlChange(channel: 0, controller: 6, value: 127),
            .noteOn(channel: 0, note: 99, velocity: 127),
            .controlChange(channel: 0, controller: 99, value: 64),
        ] {
            rig.coordinator.midi(event, source: Rig.lc6000.id)
        }
        // Python's {:<50}: pads to 50, never cuts a longer message.
        let pad = { (s: String) in s + String(repeating: " ", count: max(0, 50 - s.count)) }
        #expect(events.monitor == [
            "      12.346  ch1  " + pad("note_on channel=0 note=1 velocity=127 time=0") + " play",
            "      12.346  ch1  " + pad("note_off channel=0 note=1 velocity=0 time=0") + " play",
            "      12.346  ch1  " + pad("note_on channel=0 note=32 velocity=127 time=0") + " pad1",
            "      12.346  ch1  " + pad("control_change channel=0 control=55 value=1 time=0") + " jog",
            "      12.346  ch1  " + pad("control_change channel=0 control=6 value=127 time=0") + " select_turn",
            "      12.346  ch1  " + pad("note_on channel=0 note=99 velocity=127 time=0") + " UNMAPPED",
            "      12.346  ch1  " + pad("control_change channel=0 control=99 value=64 time=0") + " UNMAPPED",
        ])
    }

    @Test("The monitor shows every channel from the controller, even one the bridge ignores, as Python's did")
    func monitorShowsEveryChannel() throws {
        let (rig, events) = try Self.openRig()
        rig.osc.sent.removeAll()
        rig.coordinator.midi(.noteOn(channel: 1, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(events.monitor.count == 1)
        #expect(events.monitor.first?.contains("  ch2  note_on channel=1 note=1 velocity=127 time=0") == true)
        #expect(rig.osc.sent == [])
    }

    @Test("Closing Diagnostics (clearing the sink) stops the events: nothing is built for a closed window")
    func closingStopsEvents() throws {
        let (rig, events) = try Self.openRig()
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.diagnostics = nil
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        #expect(events.all.count == 2)   // the Play press: its MIDI in, and its PlayPause out
    }

    @Test("The OSC log shows what is sent and received, in the Python bridge's --verbose words")
    func oscLog() throws {
        let (rig, events) = try Self.openRig()
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Progress", [.float(0.25)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TrackInfo", [.string("Song"), .float(128), .int(8)]))
        #expect(events.osc == [
            "OSC -> /Syndicate/Deck/1/PlayPause 1",
            "OSC <- /Syndicate/Deck/1/Playing 1",
            "OSC <- /Syndicate/Deck/1/Progress 0.25",
            "OSC <- /Syndicate/Deck/1/TrackInfo Song 128.0 8",
        ])
    }

    /// The controller output's sends since the last call, as (note, velocity).
    static func takeSent(_ rig: Rig) -> [(UInt8, UInt8)] {
        let output = rig.midi.outputs[Rig.lc6000Out.id]
        defer { output?.sent.removeAll() }
        return (output?.sent ?? []).compactMap { if case let .noteOn(_, note, velocity) = $0 { (note, velocity) } else { nil } }
    }

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    /// The default profile's pads (32-39) and the platter ring (40).
    static let padsAndRing: [UInt8] = [32, 33, 34, 35, 36, 37, 38, 39, 40]

    @Test("The LED sweep steps the pads and ring through all 64 colors, 0.6 s apart, captioned as Python's led-sweep")
    func sweepColors() throws {
        let (rig, events) = try Self.openRig()
        rig.clock.now = 100
        _ = Self.takeSent(rig)

        rig.coordinator.startLEDSweep()
        #expect(Self.takeSent(rig).map(\.0) == Self.padsAndRing)
        #expect(events.sweep == [
            "Color sweep: velocity shown on every pad and the ring. Note what each looks like.",
            "  velocity  0 (0x00) = rgb222 r0 g0 b0",
        ])

        Self.tick(rig, at: 100.3)
        #expect(Self.takeSent(rig).isEmpty)
        Self.tick(rig, at: 100.601)
        #expect(Self.takeSent(rig).map(\.1) == Array(repeating: 1, count: 9))
        #expect(events.sweep.last == "  velocity  1 (0x01) = rgb222 r0 g0 b1")

        Self.tick(rig, at: 100 + 45 * 0.6 + 0.001)
        #expect(Self.takeSent(rig).suffix(9).map(\.1) == Array(repeating: 45, count: 9))
        #expect(events.sweep.last == "  velocity 45 (0x2D) = rgb222 r2 g3 b1")
        Self.tick(rig, at: 100 + 63 * 0.6 + 0.001)
        #expect(events.sweep.last == "  velocity 63 (0x3F) = rgb222 r3 g3 b3")
    }
}
