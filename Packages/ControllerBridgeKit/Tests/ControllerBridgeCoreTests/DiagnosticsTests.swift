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

    @Test("After the colors, the pads and ring go off; then every other note lights full, dim, then off, 0.2 s apart")
    func sweepButtons() throws {
        let (rig, events) = try Self.openRig()
        rig.clock.now = 100
        rig.coordinator.startLEDSweep()
        Self.tick(rig, at: 100 + 63 * 0.6 + 0.001)
        _ = Self.takeSent(rig)

        Self.tick(rig, at: 100 + 64 * 0.6 + 0.001)
        #expect(events.sweep.last == "Button sweep: each note at full, then dim, then off.")
        let start = Self.takeSent(rig)
        #expect(start.prefix(9).map(\.0) == Self.padsAndRing)
        #expect(start.prefix(9).map(\.1) == Array(repeating: 0, count: 9))
        #expect(start.dropFirst(9).map { [$0.0, $0.1] } == [[0, 127]])

        Self.tick(rig, at: 100 + 64 * 0.6 + 0.201)
        Self.tick(rig, at: 100 + 64 * 0.6 + 0.401)
        #expect(Self.takeSent(rig).map { [$0.0, $0.1] } == [[0, 1], [0, 0]])
        #expect(events.sweep.last == "  note 0")

        // Run to the end: every note but the pads and ring, each at 127, 1, 0.
        Self.tick(rig, at: 1000)
        let rest = Self.takeSent(rig)
        let expectedNotes = (UInt8(1)...127).filter { !Self.padsAndRing.contains($0) }
        let expected: [[UInt8]] = expectedNotes.flatMap { [[$0, 127], [$0, 1], [$0, 0]] }
        // After the sweep's own sends, the bridge repaints its LEDs (sweepHoldsThenRepaints).
        #expect(rest.prefix(expected.count).map { [$0.0, $0.1] } == expected)
        #expect(events.sweep.last == "LED sweep done.")
        Self.tick(rig, at: 2000)
        #expect(Self.takeSent(rig).isEmpty)
    }

    @Test("During a sweep the bridge's own LED writes wait; when the sweep ends, every LED repaints from the current state")
    func sweepHoldsThenRepaints() throws {
        let (rig, _) = try Self.openRig()
        rig.clock.now = 100
        rig.coordinator.startLEDSweep()
        _ = Self.takeSent(rig)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        #expect(Self.takeSent(rig).isEmpty)
        #expect(rig.coordinator.isSweeping)
        #expect(rig.coordinator.status.sweeping)

        Self.tick(rig, at: 1000)
        #expect(!rig.coordinator.isSweeping)
        #expect(!rig.coordinator.status.sweeping)
        #expect(rig.leds[1] == 127)     // Play, from the Playing 1 that arrived mid-sweep
        #expect(rig.leds[2] == 1)       // Cue: dim, no track loaded
        #expect(rig.leds[32] == 0)      // pad 1: no cue
    }

    @Test("Stopping a sweep part-way sends nothing more on later ticks, and repaints the LEDs")
    func cancelSweep() throws {
        let (rig, events) = try Self.openRig()
        rig.clock.now = 100
        rig.coordinator.startLEDSweep()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        Self.tick(rig, at: 101.3)
        _ = Self.takeSent(rig)

        rig.coordinator.stopLEDSweep()
        #expect(events.sweep.last == "LED sweep stopped.")
        #expect(rig.leds[1] == 127)
        #expect(rig.leds[32] == 0)
        _ = Self.takeSent(rig)
        Self.tick(rig, at: 200)
        #expect(Self.takeSent(rig).isEmpty)
        #expect(!rig.coordinator.isSweeping)
        #expect(!rig.coordinator.status.sweeping)
    }

    @Test("With no controller output open, the sweep says so and sends nothing")
    func sweepNeedsOutput() throws {
        let rig = try Rig()
        rig.midi.destinations = []
        rig.coordinator.start()
        let events = Events()
        rig.coordinator.diagnostics = { events.all.append($0) }
        rig.coordinator.startLEDSweep()
        #expect(events.sweep == ["No controller output is open, so there is nothing to sweep."])
        #expect(!rig.coordinator.isSweeping)
    }

    @Test("The sweep's pad and ring notes come from the active profile, not the LC6000's")
    func sweepUsesProfileNotes() throws {
        let mapping = try Mapping.bundledDefault(overriddenBy: Data(#"""
            { "notes": { "pads": [50, 51, 52, 53, 54, 55, 56, 57] }, "leds": { "ring": 60 } }
            """#.utf8))
        let midi = Rig.FakeMIDISystem(sources: [Rig.lc6000], destinations: [Rig.lc6000Out])
        let coordinator = Coordinator(mapping: mapping, midi: midi, osc: Rig.FakeOSC(), clock: Rig.FakeClock(), log: Rig.FakeLog())
        coordinator.start()
        midi.outputs[Rig.lc6000Out.id]?.sent.removeAll()
        coordinator.startLEDSweep()
        let notes = (midi.outputs[Rig.lc6000Out.id]?.sent ?? []).compactMap { if case let .noteOn(_, note, _) = $0 { note } else { nil } }
        #expect(notes == [50, 51, 52, 53, 54, 55, 56, 57, 60])
    }

    @Test("A monitor line splits into its message and mapping label, which join back to the same text; UNMAPPED is flagged")
    func monitorLineParts() {
        let unmapped = DiagnosticEvent.midiIn(.noteOn(channel: 0, note: 99, velocity: 127), label: "UNMAPPED", at: 1.5)
        let parts = unmapped.lineParts
        #expect(parts.message + parts.label == unmapped.text)
        #expect(parts.label == "UNMAPPED")
        #expect(parts.isUnmapped)

        let play = DiagnosticEvent.midiIn(.noteOn(channel: 0, note: 1, velocity: 127), label: "play", at: 2)
        #expect(play.lineParts.label == "play")
        #expect(!play.lineParts.isUnmapped)

        let osc = DiagnosticEvent.oscOut(OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)]))
        #expect(osc.lineParts.message == osc.text)
        #expect(osc.lineParts.label == "")
    }
}
