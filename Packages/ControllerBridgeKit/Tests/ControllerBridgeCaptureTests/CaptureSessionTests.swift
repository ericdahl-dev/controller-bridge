import ControllerBridgeCapture
import Foundation
import Testing

/// A capture session (#185): it walks the prompt list, credits each message to the current step, and moves on when
/// the owner confirms, redoes or skips.
@Suite("Capture session")
struct CaptureSessionTests {
    static let prompts = [
        CapturePrompt(id: "deck1.play", text: "Press Play on deck 1.", gesture: .press),
        CapturePrompt(id: "deck1.cue", text: "Press Cue on deck 1.", gesture: .press),
        CapturePrompt(id: "deck1.sync", text: "Press Sync on deck 1.", gesture: .press),
    ]

    static func session() -> CaptureSession {
        CaptureSession(
            appVersion: "1.2.0", device: "LC6000 PRIME",
            ports: CapturePorts(input: ["LC6000 PRIME"], output: ["LC6000 PRIME"]), prompts: prompts
        )
    }

    @Test("Confirm keeps the step's messages and moves on; redo throws away the take; skip records nothing")
    func confirmRedoSkip() {
        var session = Self.session()
        #expect(session.current?.id == "deck1.play")

        // Host clock seconds (here since 1970): the file keeps only ms from the step's first message.
        session.receive([0x90, 0x01, 0x7F], at: 1_731_700_000.000)
        session.receive([0x80, 0x01, 0x00], at: 1_731_700_000.120)
        session.confirm()
        #expect(session.current?.id == "deck1.cue")

        session.receive([0x90, 0x03, 0x7F], at: 1_731_700_005.000)  // the wrong button
        session.redo()
        #expect(session.current?.id == "deck1.cue")
        session.receive([0x90, 0x02, 0x7F], at: 1_731_700_009.000)
        session.receive([0x80, 0x02, 0x00], at: 1_731_700_009.250)
        session.confirm()

        session.skip()
        #expect(session.current == nil)

        let steps = session.file.steps
        #expect(steps.map(\.prompt) == ["deck1.play", "deck1.cue", "deck1.sync"])
        #expect(steps.map(\.status) == [.confirmed, .confirmed, .skipped])
        #expect(steps[0].messages == [CaptureMessage(t: 0, bytes: [0x90, 0x01, 0x7F]), CaptureMessage(t: 120, bytes: [0x80, 0x01, 0x00])])
        #expect(steps[1].messages == [CaptureMessage(t: 0, bytes: [0x90, 0x02, 0x7F]), CaptureMessage(t: 250, bytes: [0x80, 0x02, 0x00])])
        #expect(steps[2].messages == [])
    }

    @Test("The file carries the device, ports, app version, prompt list and the owner's optional note")
    func fileHeader() {
        var session = Self.session()
        #expect(session.file.note == nil)
        session.note = "Firmware 1.3"
        let file = session.file
        #expect(file.format == 1)
        #expect(file.appVersion == "1.2.0")
        #expect(file.device == "LC6000 PRIME")
        #expect(file.ports == CapturePorts(input: ["LC6000 PRIME"], output: ["LC6000 PRIME"]))
        #expect(file.prompts == Self.prompts)
        #expect(file.note == "Firmware 1.3")
    }

    @Test("LED answers belong to the current step: kept on confirm, thrown away with a redo")
    func ledAnswers() {
        var session = Self.session()
        session.receive([0x90, 0x01, 0x7F], at: 0)
        session.answerLED(LEDAnswer(sent: [0x90, 0x01, 0x30], lit: true, color: "green"))
        session.redo()
        session.receive([0x90, 0x01, 0x7F], at: 1)
        session.answerLED(LEDAnswer(sent: [0x90, 0x01, 0x30], lit: true, color: "red"))
        session.answerLED(LEDAnswer(sent: [0x90, 0x01, 0x00], lit: false))
        session.confirm()
        #expect(session.file.steps.first?.leds == [
            LEDAnswer(sent: [0x90, 0x01, 0x30], lit: true, color: "red"),
            LEDAnswer(sent: [0x90, 0x01, 0x00], lit: false),
        ])
    }

    @Test("Nothing in the file identifies the owner: no clock time, no fields beyond the format's, and the note only if typed")
    func privacy() throws {
        var session = Self.session()
        session.receive([0x90, 0x01, 0x7F], at: 1_731_700_000.000)
        session.receive([0x80, 0x01, 0x00], at: 1_731_700_000.120)
        session.confirm()
        let data = try session.file.encoded()
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("17317"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["format", "app_version", "device", "ports", "prompts", "noise", "steps"])
    }

    @Test("Each message and control says which input port it came on, as an index into the file's input ports")
    func ports() {
        var session = CaptureSession(
            appVersion: "1.2.0", device: "LC6000 PRIME",
            ports: CapturePorts(input: ["LC6000 PRIME", "LC6000 PRIME WD"], output: ["LC6000 PRIME"]),
            prompts: [CapturePrompt(id: "deck1.play", text: "Press Play on deck 1.", gesture: .press)]
        )
        session.receive([0x90, 0x01, 0x7F], at: 0.0, port: 1)
        session.receive([0x90, 0x01, 0x7F], at: 0.1)
        session.receive([0x80, 0x01, 0x00], at: 0.2)
        session.confirm()
        let step = session.file.steps[0]
        #expect(step.messages.map(\.port) == [1, 0, 0])
        #expect(step.controls.map(\.port) == [1, 0])
        #expect(step.controls.map(\.release) == [nil, .noteOff])
    }
}
