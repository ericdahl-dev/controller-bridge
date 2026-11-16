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

    @Test("A 7-bit knob is a CC with its number, channel and values in order")
    func sevenBitCC() {
        #expect(Self.controls(OtherTraffic.knob, gesture: .move) == [
            ControlFacts(kind: .cc, channel: 2, number: 22, encoding: .absolute, first: 10, last: 20, min: 10, max: 20),
        ])
    }

    @Test("A 14-bit pair is one control: LC6000 jog is CC 17 with LSB 49, read as 14-bit values")
    func jogPair() {
        #expect(Self.controls(LC6000Traffic.jogSpin, gesture: .turn) == [
            ControlFacts(kind: .cc, channel: 1, number: 17, lsb: 49, encoding: .absolute, first: 8000, last: 8200, min: 8000, max: 8200),
        ])
    }

    @Test("A pair needn't be n and n+32: LC6000 Needle Drop is CC 64 with LSB 65, MSB first")
    func needlePair() {
        #expect(Self.controls(LC6000Traffic.needleSlide, gesture: .move) == [
            ControlFacts(kind: .cc, channel: 1, number: 64, lsb: 65, encoding: .absolute, first: 0, last: 16383, min: 0, max: 16383),
        ])
    }

    @Test("An encoder turned right then left is relative: LC6000 browse is CC 6, two's complement")
    func twosComplement() {
        #expect(Self.controls(LC6000Traffic.browseTurn, gesture: .turn) == [
            ControlFacts(kind: .cc, channel: 1, number: 6, encoding: .twosComplement, first: 1, last: 127, min: 1, max: 127),
        ])
    }

    @Test("Offset-64 and sign-magnitude encoders are told apart by which values mean back")
    func otherRelativeFormats() {
        #expect(Self.controls(OtherTraffic.offset64Turn, gesture: .turn).map(\.encoding) == [.offset64])
        #expect(Self.controls(OtherTraffic.signMagnitudeTurn, gesture: .turn).map(\.encoding) == [.signMagnitude])
    }

    @Test("A turn one way only in an ambiguous band leaves the encoding unknown rather than guessing")
    func ambiguousTurn() {
        #expect(Self.controls(OtherTraffic.oneWayTurn, gesture: .turn).map(\.encoding) == [nil])
    }

    @Test("A knob turned slowly near the bottom stays absolute: its values walk, they don't repeat")
    func slowAbsoluteKnob() {
        #expect(Self.controls(OtherTraffic.knob, gesture: .turn).map(\.encoding) == [.absolute])
    }

    @Test("A fader keeps its values in order, so the prompt's gesture gives its direction: LC6000 pitch, bottom to top, ends at 0")
    func pitchDirection() {
        let pitch = Self.controls(LC6000Traffic.pitchUp, gesture: .move)
        #expect(pitch == [
            ControlFacts(kind: .cc, channel: 1, number: 8, lsb: 40, encoding: .absolute, first: 16383, last: 0, min: 0, max: 16383),
        ])
    }

    @Test("Pitch bend is its own kind, with a channel, 14-bit values and no number")
    func pitchBend() {
        #expect(Self.controls(OtherTraffic.pitchBend, gesture: .move) == [
            ControlFacts(kind: .pitchBend, channel: 2, first: 8192, last: 16383, min: 8192, max: 16383),
        ])
    }

    @Test("A step lists every control it heard, in order: the jog's touch note 40, then its position on CC 17/49")
    func jogWithTouch() {
        #expect(Self.controls(LC6000Traffic.jogTouchTurn, gesture: .turn) == [
            ControlFacts(kind: .note, channel: 1, number: 40, release: .noteOff, first: 127, last: 127, min: 127, max: 127),
            ControlFacts(kind: .cc, channel: 1, number: 17, lsb: 49, encoding: .absolute, first: 100, last: 180, min: 100, max: 180),
        ])
    }

    @Test("Needle Drop's touch note 70 is listed with its position on CC 64/65")
    func needleWithTouch() {
        #expect(Self.controls(LC6000Traffic.needleTouchSlide, gesture: .move) == [
            ControlFacts(kind: .note, channel: 1, number: 70, release: .noteOff, first: 127, last: 127, min: 127, max: 127),
            ControlFacts(kind: .cc, channel: 1, number: 64, lsb: 65, encoding: .absolute, first: 2000, last: 9000, min: 2000, max: 9000),
        ])
    }
}
