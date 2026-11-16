import ControllerBridgeCapture
import Testing

/// Noise (#185): a message that keeps coming whatever the owner touches, like the LC6000's note 52 heartbeat in host
/// mode, isn't credited to a step. The prompt list starts with an idle step (hands off) to learn it while capturing.
@Suite("Capture noise")
struct NoiseTests {
    typealias Take = [(time: Double, bytes: [UInt8])]

    static func session(_ prompts: [CapturePrompt]) -> CaptureSession {
        CaptureSession(appVersion: "1.2.0", device: "LC6000 PRIME", ports: CapturePorts(input: [], output: []), prompts: prompts)
    }

    static let idle = CapturePrompt(id: "idle", text: "Don't touch anything for a few seconds.", gesture: .idle)
    static let play = CapturePrompt(id: "deck1.play", text: "Press Play on deck 1.", gesture: .press)
    static let cue = CapturePrompt(id: "deck1.cue", text: "Press Cue on deck 1.", gesture: .press)
    static let shift = CapturePrompt(id: "deck1.shift", text: "Press Shift on deck 1.", gesture: .press)
    static let jogTouch = CapturePrompt(id: "deck1.jog.touch", text: "Touch and turn the jog.", gesture: .turn)
    static let jogEdge = CapturePrompt(id: "deck1.jog.edge", text: "Spin the jog's edge.", gesture: .turn)

    static func merged(_ takes: Take...) -> Take { takes.joined().sorted { $0.time < $1.time } }

    static func feed(_ session: inout CaptureSession, _ take: Take) {
        for message in take { session.receive(message.bytes, at: message.time) }
    }

    @Test("What arrives during the idle step is noise: Play's step credits only Play, live and in the file")
    func idleStepLearnsNoise() {
        var session = Self.session([Self.idle, Self.play])
        Self.feed(&session, LC6000Traffic.heartbeat(from: 0, count: 6))
        session.confirm()

        Self.feed(&session, Self.merged(LC6000Traffic.heartbeat(from: 10, count: 2), LC6000Traffic.play.map { ($0.time + 10.2, $0.bytes) }))
        let play = ControlFacts(kind: .note, channel: 1, number: 1, release: .noteOff, first: 127, last: 127, min: 127, max: 127)
        #expect(session.currentControls == [play])
        session.confirm()

        let file = session.file
        #expect(file.noise == [[0x90, 0x34], [0x91, 0x34]])
        #expect(file.steps[1].controls == [play])
        #expect(file.steps[1].messages.map(\.bytes) == [[0x90, 0x01, 0x7F], [0x80, 0x01, 0x00]])
    }

    static let shiftPress: Take = [(0.0, [0x90, 26, 0x7F]), (0.1, [0x80, 26, 0x00])]

    @Test("Without an idle step, a message in every one of three or more confirmed steps is noise once the capture ends")
    func repeatsInEveryStep() {
        var session = Self.session([Self.play, Self.cue, Self.shift])
        for (index, take) in [LC6000Traffic.play, LC6000Traffic.cue, Self.shiftPress].enumerated() {
            let start = Double(index) * 5
            Self.feed(&session, Self.merged(LC6000Traffic.heartbeat(from: start, count: 1), take.map { ($0.time + start + 0.2, $0.bytes) }))
            session.confirm()
        }

        let file = session.file
        #expect(file.noise == [[0x90, 0x34], [0x91, 0x34]])
        #expect(file.steps.map { $0.controls.compactMap(\.number) } == [[1], [2], [26]])
        #expect(file.steps[0].messages.map(\.bytes) == [[0x90, 0x01, 0x7F], [0x80, 0x01, 0x00]])
    }

    @Test("Two steps that share a control don't make it noise: jog touch and jog edge both send CC 17/49")
    func twoStepsShareAControl() {
        var session = Self.session([Self.jogTouch, Self.jogEdge])
        Self.feed(&session, LC6000Traffic.jogTouchTurn)
        session.confirm()
        Self.feed(&session, LC6000Traffic.jogSpin.map { ($0.time + 5, $0.bytes) })
        session.confirm()
        #expect(session.file.noise == [])
        #expect(session.file.steps[1].controls.compactMap(\.number) == [17])
    }

    @Test("Once an idle step has learned the noise, steps that share a control keep it")
    func idleStepWins() {
        var session = Self.session([Self.idle, Self.jogTouch, Self.jogEdge, Self.play])
        Self.feed(&session, LC6000Traffic.heartbeat(from: 0, count: 2))
        session.confirm()
        // Hand-built: a jog CC message rides in every later step, as if the wheel were nudged each time.
        let nudge: Take = [(0.05, [0xB0, 17, 0x3E]), (0.051, [0xB0, 49, 0x40])]
        Self.feed(&session, Self.merged(LC6000Traffic.jogTouchTurn, nudge).map { ($0.time + 5, $0.bytes) })
        session.confirm()
        Self.feed(&session, LC6000Traffic.jogSpin.map { ($0.time + 10, $0.bytes) })
        session.confirm()
        Self.feed(&session, Self.merged(LC6000Traffic.play, nudge).map { ($0.time + 15, $0.bytes) })
        session.confirm()
        #expect(session.file.noise == [[0x90, 0x34], [0x91, 0x34]])
        #expect(session.file.steps[3].controls.compactMap(\.number) == [1, 17])
    }
}
