import ControllerBridgeCapture
import Testing

/// What a capture infers about the control in each step (#185), checked against LC6000 traffic with known answers.
@Suite("Capture inference")
struct InferenceTests {
    /// The controls a session infers for one confirmed take of one prompt.
    static func controls(_ take: [(time: Double, bytes: [UInt8])], gesture: CaptureGesture = .press) -> [ControlFacts] {
        var session = CaptureSession(
            appVersion: "1.2.0", device: "Test", ports: CapturePorts(input: [], output: []),
            prompts: [CapturePrompt(id: "step", text: "Do it.", gesture: gesture)]
        )
        for message in take { session.receive(message.bytes, at: message.time) }
        session.confirm()
        return session.file.steps.first?.controls ?? []
    }

    @Test("A button is a note: LC6000 Play is note 1 and Cue note 2 on channel 1, released with a note-off")
    func notes() {
        #expect(Self.controls(LC6000Traffic.play) == [
            ControlFacts(kind: .note, channel: 1, number: 1, release: .noteOff, first: 127, last: 127, min: 127, max: 127),
        ])
        #expect(Self.controls(LC6000Traffic.cue) == [
            ControlFacts(kind: .note, channel: 1, number: 2, release: .noteOff, first: 127, last: 127, min: 127, max: 127),
        ])
    }

    @Test("A button released with a note-on at velocity 0 says so, and its channel is 1-based")
    func noteOnZero() {
        #expect(Self.controls(OtherTraffic.noteOnZeroRelease) == [
            ControlFacts(kind: .note, channel: 3, number: 11, release: .noteOnZero, first: 127, last: 127, min: 127, max: 127),
        ])
    }
}
