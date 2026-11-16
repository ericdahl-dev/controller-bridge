import ControllerBridgeCapture
import Testing

/// A shifted step shows how Shift changed the control, live (#229).
@Suite("Capture shift readout")
struct ShiftReadoutTests {
    /// Play, then Play with Shift held, on a flow whose base step is `base` (skipped when nil).
    static func shifted(base: [[UInt8]]?, shifted: [[UInt8]]) -> CaptureFlow {
        var flow = CaptureFlow(prompts: [
            CapturePrompt(id: "deck1.play", text: "Press Play.", gesture: .press),
            CapturePrompt(id: "deck1.play.shift", text: "Hold Shift and press Play.", gesture: .press, shiftedOf: "deck1.play"),
        ], appVersion: "1.2.0")
        flow.start(device: "Test", ports: CapturePorts(input: [], output: []), at: 0)
        if let base {
            for (i, bytes) in base.enumerated() { flow.receive(bytes, at: 1 + Double(i) * 0.1) }
            flow.next(at: 2)
        } else {
            flow.skip(at: 2)
        }
        for (i, bytes) in shifted.enumerated() { flow.receive(bytes, at: 3 + Double(i) * 0.2) }
        flow.tick(at: 4)
        return flow
    }

    static let play: [[UInt8]] = [[0x90, 1, 0x7F], [0x80, 1, 0]]

    @Test("LC6000: Shift sends Play unchanged")
    func same() {
        let flow = Self.shifted(base: Self.play, shifted: [[0x90, 26, 0x7F], [0x90, 1, 0x7F], [0x80, 1, 0], [0x80, 26, 0]])
        #expect(flow.shiftReadout == "Shift: same message")
    }

    @Test("Shift moving the note, the channel, or both")
    func offsets() {
        #expect(Self.shifted(base: [[0x90, 11, 0x7F]], shifted: [[0x90, 63, 0x7F], [0x90, 75, 0x7F]]).shiftReadout == "Shift: note +64")
        #expect(Self.shifted(base: [[0x90, 11, 0x7F]], shifted: [[0x90, 63, 0x7F], [0x91, 11, 0x7F]]).shiftReadout == "Shift: channel +1")
        #expect(Self.shifted(base: [[0x91, 75, 0x7F]], shifted: [[0x90, 63, 0x7F], [0x90, 11, 0x7F]]).shiftReadout
            == "Shift: channel -1, note -64")
        #expect(Self.shifted(base: [[0xB0, 6, 1]], shifted: [[0x90, 63, 0x7F], [0xB0, 70, 1]]).shiftReadout == "Shift: CC +64")
    }

    @Test("No readout before the shifted control arrives, or when the step it repeats was skipped")
    func none() {
        #expect(Self.shifted(base: Self.play, shifted: []).shiftReadout == nil)
        #expect(Self.shifted(base: nil, shifted: [[0x90, 26, 0x7F], [0x90, 1, 0x7F]]).shiftReadout == nil)
    }

    @Test("VoiceOver hears the offset with the detection")
    func announced() {
        var flow = Self.shifted(base: Self.play, shifted: [])
        _ = flow.takeAnnouncement()  // the step
        flow.receive([0x90, 26, 0x7F], at: 5)
        flow.receive([0x90, 1, 0x7F], at: 5.5)
        #expect(flow.takeAnnouncement() == "Detected: Note 1 on channel 1. Shift: same message.")
    }
}
