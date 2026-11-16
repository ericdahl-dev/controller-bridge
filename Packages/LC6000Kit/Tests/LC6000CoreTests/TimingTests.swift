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
}
