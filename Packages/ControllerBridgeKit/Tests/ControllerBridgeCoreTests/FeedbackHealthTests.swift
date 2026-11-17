@testable import ControllerBridgeCore
import Testing

/// Feedback health (#385): liveness, Resend timing, the answer and the subscription verdict, on a plain clock. Quiet
/// period 2 s, answer window 0.5 s.
@Suite("Feedback health: liveness")
struct FeedbackHealthLivenessTests {
    static func health() -> FeedbackHealth { FeedbackHealth(quiet: 2, answerWindow: 0.5) }
    static let beat = OSCMessage("/Syndicate/Header/Clock", [.int(1)])

    @Test("Waiting until the first message, then live")
    func firstMessage() {
        var health = Self.health()
        #expect(health.feedback == .waiting)
        #expect(health.messageArrived(Self.beat, at: 0) == FeedbackHealth.Output())
        #expect(health.feedback == .live)
    }

    @Test("Quiet for the quiet period: one Resend, and never a second while it waits")
    func quietAsks() {
        var health = Self.health()
        _ = health.messageArrived(Self.beat, at: 0)
        #expect(health.tick(at: 1.9, required: []).resend == false)
        #expect(health.tick(at: 2.0, required: []).resend == true)
        #expect(health.tick(at: 2.1, required: []).resend == false)
        #expect(health.requestResend(at: 2.2) == false)
    }

    @Test("No answer within the window: stale, once; then asked again every quiet period")
    func noAnswerStops() {
        var health = Self.health()
        _ = health.messageArrived(Self.beat, at: 0)
        _ = health.tick(at: 2.0, required: [])
        #expect(health.tick(at: 2.4, required: []).event == nil)
        let stopped = health.tick(at: 2.5, required: [])
        #expect(stopped.event == .stopped)
        #expect(health.feedback == .stale)
        #expect(health.tick(at: 3.0, required: []).event == nil)
        #expect(health.tick(at: 3.9, required: []).resend == false)
        #expect(health.tick(at: 4.0, required: []).resend == true)
    }

    @Test("Back after stale: live and .back, with a Resend unless it's the answer to one in its window")
    func comesBack() {
        var health = Self.health()
        _ = health.messageArrived(Self.beat, at: 0)
        _ = health.tick(at: 2.0, required: [])
        _ = health.tick(at: 2.5, required: [])
        #expect(health.messageArrived(Self.beat, at: 3.0) == FeedbackHealth.Output(resend: true, event: .back))
        #expect(health.feedback == .live)

        var answered = Self.health()
        _ = answered.messageArrived(Self.beat, at: 0)
        _ = answered.tick(at: 2.0, required: [])
        _ = answered.tick(at: 2.5, required: [])
        _ = answered.tick(at: 4.5, required: [])               // asked again at 4.5
        #expect(answered.messageArrived(Self.beat, at: 4.6) == FeedbackHealth.Output(event: .back))
    }

    @Test("resync drops a waiting Resend and asks again")
    func resync() {
        var health = Self.health()
        #expect(health.requestResend(at: 0) == true)
        #expect(health.requestResend(at: 0.1) == false)
        #expect(health.resync(at: 0.2) == true)
    }
}
