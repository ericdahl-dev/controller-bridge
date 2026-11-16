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
}
