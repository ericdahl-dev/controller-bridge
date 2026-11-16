import ControllerBridgeCore
import Foundation
import Testing

/// Feedback liveness (#21). Syndicate sends feedback only when a value changes, so a quiet Syndicate and a gone one
/// look the same. After `osc.feedback_quiet_ms` (10 s) of quiet the bridge sends one Resend: Syndicate answers it with
/// every subscribed value, and always ColorPalette (user guide §14.10). With no answer within `osc.feedback_answer_ms`
/// (2 s), feedback counts as stopped.
@Suite("Feedback liveness")
struct LivenessTests {
    static let resend = OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])

    /// Started at t = 0, with one feedback message at t = 0.5 so feedback is live, and everything sent so far cleared.
    static func liveRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.5
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.osc.sent.removeAll()
        return rig
    }

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    @Test("After 10 s with no feedback, the bridge asks Syndicate to resend, once")
    func quietSendsOneProbe() throws {
        let rig = try Self.liveRig()
        Self.tick(rig, at: 10.4)
        #expect(rig.osc.sent == [])

        Self.tick(rig, at: 10.5)
        #expect(rig.osc.sent == [Self.resend])

        for time in [10.6, 11.0, 12.0, 12.4] { Self.tick(rig, at: time) }
        #expect(rig.osc.sent == [Self.resend])
    }

    @Test("Any answer within 2 s keeps feedback live: the LEDs stay as they are, and the next probe waits another 10 s")
    func answerKeepsLive() throws {
        let rig = try Self.liveRig()
        Self.tick(rig, at: 10.5)
        rig.clock.now = 11.0
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        for time in [12.6, 15.0, 20.9] { Self.tick(rig, at: time) }

        #expect(rig.leds[1] == 127)
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.osc.sent == [Self.resend])
        Self.tick(rig, at: 21.0)
        #expect(rig.osc.sent == [Self.resend, Self.resend])
    }

    @Test("With no answer within 2 s, feedback is stale: Syndicate's state is cleared, the bridge's own state stays")
    func noAnswerGoesStale() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.5
        for (path, value) in [("Loaded", 1), ("Playing", 1), ("Sync", 1), ("Loop", 1)] {
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [.int(Int32(value))]))
        }
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Cues", [.int(1), .string("Drop")] + Array(repeating: [OSCArgument.int(0), .string("")], count: 7).flatMap { $0 }))
        rig.coordinator.midi(.noteOn(channel: 0, note: 22, velocity: 127), source: Rig.lc6000.id)   // Key Lock on
        // Play, Sync, Master, Loop In, pad 1 (red, 48), ring (11) and Key Lock are lit.
        #expect([rig.leds[1], rig.leds[20], rig.leds[21], rig.leds[8], rig.leds[32], rig.leds[40], rig.leds[22]]
            == [127, 127, 127, 127, 48, 11, 127])

        Self.tick(rig, at: 10.5)
        Self.tick(rig, at: 12.4)
        #expect(rig.coordinator.status.feedback == .live)
        Self.tick(rig, at: 12.5)

        #expect(rig.coordinator.status.feedback == .stale)
        // Syndicate's LEDs go to idle: buttons dim (1), pads and ring off. Key Lock is the bridge's own: still lit.
        #expect([rig.leds[1], rig.leds[20], rig.leds[21], rig.leds[8], rig.leds[32], rig.leds[40], rig.leds[22]]
            == [1, 1, 1, 1, 0, 0, 127])
        #expect(rig.log.lines.contains("Syndicate feedback stopped"))
        #expect(rig.coordinator.status.lastDropout == "Syndicate feedback stopped")
    }
}
