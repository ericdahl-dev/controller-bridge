import ControllerBridgeCapture
import Testing

/// Inference on read (#190): a capture written without inferred facts (the web capture's) gets them from its raw
/// messages, by the same inference the app's capture runs.
@Suite("Capture file inferred")
struct InferredTests {
    static let app = DemoCaptureTests.walked().flow.file!

    /// The capture as the web writes it: raw messages and noise, no controls, LED answers or Shift layers.
    static var stripped: CaptureFile {
        var file = app
        file.steps = file.steps.map { CaptureStep(prompt: $0.prompt, status: $0.status, messages: $0.messages) }
        return file
    }

    @Test("An app capture comes out unchanged")
    func appUnchanged() {
        #expect(Self.app.inferred() == Self.app)
    }

    @Test("A capture without controls or Shift layers gets the app's, from its messages; noise is kept as written")
    func webFilled() {
        let filled = Self.stripped.inferred()
        #expect(filled.steps.map(\.controls) == Self.app.steps.map(\.controls))
        #expect(filled.steps.map(\.shift) == Self.app.steps.map(\.shift))
        #expect(filled.noise == Self.app.noise)
        #expect(Self.app.steps.contains { $0.shift != nil }, "the demo capture has a Shift layer to infer")
    }

    @Test("Tails keep their flag through inference (#229): Play's release in Cue's step stays a tail, and the file is unchanged")
    func tailsKept() throws {
        let play = CapturePrompt(id: "deck1.play", text: "Play", gesture: .press)
        let cue = CapturePrompt(id: "deck1.cue", text: "Cue", gesture: .press)
        var session = CaptureSession(appVersion: "1.2.0", device: "Test", ports: CapturePorts(input: ["Test"], output: []), prompts: [play, cue])
        session.receive([0x90, 0x0B, 0x7F], at: 1)
        session.confirm(at: 2)
        session.receive([0x90, 0x0B, 0x00], at: 2.1)
        session.receive([0x90, 0x0C, 0x7F], at: 2.3)
        session.receive([0x90, 0x0C, 0x00], at: 2.4)
        session.confirm(at: 3)
        let file = session.file
        #expect(file.steps[1].messages.contains { $0.tail }, "the release is in the file, flagged")
        #expect(file.inferred() == file)
    }
}
