import ControllerBridgeCapture
import Testing

/// A step repeated with Shift held (#185): the Shift button isn't the control, and the step records how the control's
/// message differs from the unshifted step's.
@Suite("Capture shift layer")
struct ShiftLayerTests {
    static func steps(base: [(time: Double, bytes: [UInt8])], shifted: [(time: Double, bytes: [UInt8])], skipBase: Bool = false) -> [CaptureStep] {
        var session = CaptureSession(
            appVersion: "1.2.0", device: "Test", ports: CapturePorts(input: [], output: []),
            prompts: [
                CapturePrompt(id: "deck1.play", text: "Press Play on deck 1.", gesture: .press),
                CapturePrompt(id: "deck1.play.shift", text: "Hold Shift and press Play.", gesture: .press, shiftedOf: "deck1.play"),
            ]
        )
        if skipBase {
            session.skip()
        } else {
            for message in base { session.receive(message.bytes, at: message.time) }
            session.confirm()
        }
        for message in shifted { session.receive(message.bytes, at: message.time) }
        session.confirm()
        return session.file.steps
    }

    @Test("LC6000: Shift (note 26) held around Play isn't credited, and Play is unchanged: offsets 0 and 0")
    func lc6000() {
        let shifted = Self.steps(base: LC6000Traffic.play, shifted: LC6000Traffic.shiftPlay)[1]
        #expect(shifted.controls == [
            ControlFacts(kind: .note, channel: 1, number: 1, release: .noteOff, first: 127, last: 127, min: 127, max: 127),
        ])
        #expect(shifted.shift == ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 0))
        #expect(shifted.messages.count == 4)  // the raw messages keep Shift
    }

    @Test("A controller whose Shift moves Play from note 11 to 75 records a number offset of 64")
    func numberOffset() {
        let shifted = Self.steps(base: OtherTraffic.play, shifted: OtherTraffic.shiftPlay)[1]
        #expect(shifted.controls.map(\.number) == [75])
        #expect(shifted.shift == ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 64))
    }

    @Test("With the unshifted step skipped there's nothing to compare, so no shift layer is guessed")
    func baseSkipped() {
        let shifted = Self.steps(base: [], shifted: LC6000Traffic.shiftPlay, skipBase: true)[1]
        #expect(shifted.shift == nil)
    }

    @Test("Shift let go before Play is still Shift: it's the note already down when the other control starts")
    func shiftReleasedFirst() {
        let shifted = Self.steps(base: LC6000Traffic.play, shifted: LC6000Traffic.shiftPlayEarlyRelease)[1]
        #expect(shifted.controls.map(\.number) == [1])
        #expect(shifted.shift == ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 0))
    }
}
