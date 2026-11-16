import Foundation
import LC6000Core
import Testing

/// Timing LEDs (#23). Time comes from the fake clock: set `rig.clock.now`, then `tick()`. The Play LED is note 1.
@Suite("Timing LEDs")
struct TimingTests {
    static func startedRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    @Test("While a quantized start is pending, the Play LED blinks: full for 0.25 s, then dim for 0.25 s")
    func playPendingBlinks() throws {
        let rig = try Self.startedRig()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(1)]))

        Self.tick(rig, at: 0.0)
        #expect(rig.leds[1] == 127)
        Self.tick(rig, at: 0.3)
        #expect(rig.leds[1] == 1)
        Self.tick(rig, at: 0.5)
        #expect(rig.leds[1] == 127)
        Self.tick(rig, at: 0.8)
        #expect(rig.leds[1] == 1)
    }

    @Test("When the pending start ends the blink stops: solid full once playing, dim if the start was canceled")
    func blinkStopsWhenPendingEnds() throws {
        let rig = try Self.startedRig()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(1)]))
        Self.tick(rig, at: 0.3)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(0)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        for time in [0.3, 0.5, 0.8] {
            Self.tick(rig, at: time)
            #expect(rig.leds[1] == 127)
        }

        let canceled = try Self.startedRig()
        canceled.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(1)]))
        Self.tick(canceled, at: 0.0)
        canceled.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(0)]))
        #expect(canceled.leds[1] == 1)
        Self.tick(canceled, at: 0.5)
        #expect(canceled.leds[1] == 1)
    }

    @Test("The blink only sends changes: ticks inside the same half-period send no LED message")
    func blinkSendsOnlyChanges() throws {
        let rig = try Self.startedRig()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(1)]))
        for time in stride(from: 0.0, to: 1.0, by: 0.01) { Self.tick(rig, at: time) }
        let playLED = rig.midi.outputs[Rig.lc6000Out.id]?.sent.compactMap { event -> UInt8? in
            guard case let .noteOn(_, 1, velocity) = event else { return nil }
            return velocity
        }
        // Dim at start, then on, off, on, off across the first second.
        #expect(playLED == [1, 127, 1, 127, 1])
    }

    @Test("With no controller output open, ticks send nothing, and opening it later paints the current blink state")
    func tickWithPortsClosed() throws {
        let rig = try Rig()
        rig.midi.destinations = []
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PlayPending", [.int(1)]))
        for time in [0.0, 0.3, 0.5] { Self.tick(rig, at: time) }
        #expect(rig.midi.outputs.isEmpty)
        #expect(rig.osc.sent.isEmpty)

        rig.midi.destinations = [Rig.lc6000Out]
        rig.coordinator.start()
        Self.tick(rig, at: 0.6)
        #expect(rig.leds[1] == 127)
    }

    static func cues(_ slots: [Int32]) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/1/Cues", slots.flatMap { [OSCArgument.int($0), .string($0 == 0 ? "" : "Cue")] })
    }

    static func palette(_ slot: Int32, _ red: Int32, _ green: Int32, _ blue: Int32) -> OSCMessage {
        OSCMessage("/Syndicate/ColorPalette", [.int(slot), .int(red), .int(green), .int(blue)])
    }

    @Test("A held hot-cue pad shows the brightest version of its color, and goes back to its color on release")
    func heldPadIsBrightest() throws {
        let rig = try Self.startedRig()
        // Slot 1 is navy (0, 0, 128): blue level 2, so 0b00_00_10 = 2. Brightest is (0, 0, 255): 0b00_00_11 = 3.
        // Slot 2 is dim red (40, 0, 0): it rounds to black, so it lights at the lowest red, 16. Brightest is 48.
        rig.coordinator.feedback(Self.palette(1, 0, 0, 128))
        rig.coordinator.feedback(Self.palette(2, 40, 0, 0))
        rig.coordinator.feedback(Self.cues([1, 2, 0, 0, 0, 0, 0, 0]))
        #expect([rig.leds[32], rig.leds[33]] == [2, 16])

        rig.coordinator.midi(.noteOn(channel: 0, note: 32, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOn(channel: 0, note: 33, velocity: 127), source: Rig.lc6000.id)
        #expect([rig.leds[32], rig.leds[33]] == [3, 48])

        rig.coordinator.midi(.noteOff(channel: 0, note: 32, velocity: 0), source: Rig.lc6000.id)
        #expect([rig.leds[32], rig.leds[33]] == [2, 48])
    }

    /// A started controller whose mapping sets `leds.beat_pulse`, with a track loaded so the ring is lit.
    final class PulseRig {
        let midi = Rig.FakeMIDISystem(sources: [Rig.lc6000], destinations: [Rig.lc6000Out])
        let clock = Rig.FakeClock()
        let coordinator: Coordinator

        init(beatPulse: String) throws {
            let override = Data(#"{ "leds": { "beat_pulse": "\#(beatPulse)" } }"#.utf8)
            coordinator = Coordinator(
                mapping: try Mapping.bundledDefault(overriddenBy: override),
                midi: midi, osc: Rig.FakeOSC(), clock: clock, log: Rig.FakeLog()
            )
            coordinator.start()
            coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        }

        /// The ring LED (note 40) after a tick at `time`.
        func ring(at time: Double) -> UInt8? {
            clock.now = time
            coordinator.tick()
            var latest: UInt8?
            for case let .noteOn(_, 40, velocity) in midi.outputs[Rig.lc6000Out.id]?.sent ?? [] { latest = velocity }
            return latest
        }

        /// Syndicate's master clock: beat-in-bar 1-4 on every master beat, 1 is the downbeat.
        func clockBeat(_ beat: Int32, at time: Double) {
            clock.now = time
            coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(beat)]))
        }
    }

    // The ring color (0, 128, 255) is 0b00_10_11 = 11. Pulses last pulse_ms, 100 ms by default.

    @Test("With beat pulse on, the ring is solid until a clock arrives, then lit for 100 ms after each beat")
    func ringPulsesOnBeat() throws {
        let rig = try PulseRig(beatPulse: "beat")
        #expect(rig.ring(at: 9.0) == 11)

        rig.clockBeat(2, at: 10.0)
        #expect(rig.ring(at: 10.0) == 11)
        #expect(rig.ring(at: 10.09) == 11)
        #expect(rig.ring(at: 10.11) == 0)

        rig.clockBeat(3, at: 10.5)
        #expect(rig.ring(at: 10.5) == 11)
        #expect(rig.ring(at: 10.61) == 0)
    }

    @Test("With downbeat pulse, only beat 1 of the bar lights the ring; beats 2-4 leave it off")
    func ringPulsesOnDownbeat() throws {
        let rig = try PulseRig(beatPulse: "downbeat")
        rig.clockBeat(1, at: 20.0)
        #expect(rig.ring(at: 20.05) == 11)
        #expect(rig.ring(at: 20.2) == 0)

        rig.clockBeat(2, at: 20.5)
        #expect(rig.ring(at: 20.55) == 0)
        rig.clockBeat(4, at: 21.5)
        #expect(rig.ring(at: 21.55) == 0)

        rig.clockBeat(1, at: 22.0)
        #expect(rig.ring(at: 22.05) == 11)
    }

    @Test("When the master clock stops for more than 2 s, the ring goes back to solid")
    func ringSolidWhenClockStops() throws {
        let rig = try PulseRig(beatPulse: "beat")
        rig.clockBeat(1, at: 30.0)
        #expect(rig.ring(at: 30.5) == 0)
        #expect(rig.ring(at: 31.9) == 0)
        #expect(rig.ring(at: 32.1) == 11)
    }

    @Test("A downbeat pulse at a slow tempo stays pulsing: beats 2-4 count as the clock arriving")
    func slowDownbeatKeepsPulsing() throws {
        // 60 BPM: a beat every second, a downbeat every 4 s.
        let rig = try PulseRig(beatPulse: "downbeat")
        rig.clockBeat(1, at: 40.0)
        rig.clockBeat(2, at: 41.0)
        rig.clockBeat(3, at: 42.0)
        #expect(rig.ring(at: 42.5) == 0)
        rig.clockBeat(4, at: 43.0)
        #expect(rig.ring(at: 43.5) == 0)
    }
}
