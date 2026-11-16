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
}
