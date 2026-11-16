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
}
