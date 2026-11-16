import ControllerBridgeCapture
import Testing

/// Tails across Next (#186): what the previous step's control sends just after the owner moves on (a late release,
/// a jog still spinning) isn't credited to the new step.
@Suite("Capture tails")
struct TailTests {
    static func session(_ ids: [(String, CaptureGesture, String?)]) -> CaptureSession {
        CaptureSession(
            appVersion: "1.2.0", device: "LC6000 PRIME", ports: CapturePorts(input: [], output: []),
            prompts: ids.map { CapturePrompt(id: $0.0, text: "Do it.", gesture: $0.1, shiftedOf: $0.2) }
        )
    }

    static func feed(_ session: inout CaptureSession, _ take: [(time: Double, bytes: [UInt8])], from start: Double) {
        for message in take { session.receive(message.bytes, at: message.time + start) }
    }

    @Test("A jog still spinning just after Next isn't credited to the next step")
    func jogSpinDown() {
        var session = Self.session([("deck1.jog.edge", .turn, nil), ("deck1.play", .press, nil)])
        Self.feed(&session, LC6000Traffic.jogSpin, from: 0)
        session.confirm(at: 1.0)
        Self.feed(&session, LC6000Traffic.pairs(msb: 17, lsb: 49, values: [8210, 8215]), from: 1.05)
        Self.feed(&session, LC6000Traffic.play, from: 2.0)
        session.confirm(at: 3.0)
        let play = session.file.steps[1]
        #expect(play.controls.map(\.number) == [1])
        #expect(play.messages.map(\.bytes) == [[0x90, 0x01, 0x7F], [0x80, 0x01, 0x00]])
    }

    @Test("A release whose press came before Next isn't credited, so Shift detection still sees Shift first")
    func lateRelease() {
        var session = Self.session([("deck1.play", .press, nil), ("deck1.play.shift", .press, "deck1.play")])
        session.receive([0x90, 0x01, 0x7F], at: 0.0)
        session.confirm(at: 0.1)
        session.receive([0x80, 0x01, 0x00], at: 0.2)  // Play let go after Next
        Self.feed(&session, LC6000Traffic.shiftPlay, from: 1.0)
        session.confirm(at: 2.0)
        let shifted = session.file.steps[1]
        #expect(shifted.controls.map(\.number) == [1])
        #expect(shifted.shift == ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 0))
        #expect(shifted.messages.count == 4)
    }

    @Test("The same control well after Next counts: jog touch then jog edge both send CC 17/49")
    func sameControlLater() {
        var session = Self.session([("deck1.jog.touch", .turn, nil), ("deck1.jog.edge", .turn, nil)])
        Self.feed(&session, LC6000Traffic.jogTouchTurn, from: 0)
        session.confirm(at: 1.0)
        Self.feed(&session, LC6000Traffic.jogSpin, from: 2.0)
        session.confirm(at: 3.0)
        #expect(session.file.steps[1].controls.map(\.number) == [17])
    }
}
