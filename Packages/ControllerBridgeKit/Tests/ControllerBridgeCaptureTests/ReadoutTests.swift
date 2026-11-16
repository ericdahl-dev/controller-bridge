import ControllerBridgeCapture
import Testing

/// What the capture window shows and speaks for a detected control (#186).
@Suite("Capture readout")
struct ReadoutTests {
    @Test("Short readouts, as the window shows them")
    func summaries() {
        #expect(ControlFacts(kind: .note, channel: 1, number: 1, release: .noteOff, first: 127, last: 127, min: 127, max: 127).summary
            == "Note 1 on ch 1")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 17, lsb: 49, encoding: .absolute, first: 0, last: 9, min: 0, max: 9).summary
            == "CC 17 + 49 on ch 1, 14-bit, absolute")
        #expect(ControlFacts(kind: .cc, channel: 2, number: 22, encoding: .absolute, first: 10, last: 20, min: 10, max: 20).summary
            == "CC 22 on ch 2, absolute")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 6, encoding: .twosComplement, first: 1, last: 127, min: 1, max: 127).summary
            == "CC 6 on ch 1, relative (two's complement)")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 30, encoding: .offset64, first: 65, last: 63, min: 63, max: 65).summary
            == "CC 30 on ch 1, relative (offset 64)")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 30, encoding: .signMagnitude, first: 1, last: 65, min: 1, max: 65).summary
            == "CC 30 on ch 1, relative (sign magnitude)")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 30, first: 65, last: 65, min: 65, max: 65).summary
            == "CC 30 on ch 1, encoding unclear")
        #expect(ControlFacts(kind: .pitchBend, channel: 2, first: 8192, last: 16383, min: 8192, max: 16383).summary
            == "Pitch bend on ch 2")
    }

    @Test("Spoken readouts, in words VoiceOver reads well")
    func spoken() {
        #expect(ControlFacts(kind: .note, channel: 1, number: 1, first: 127, last: 127, min: 127, max: 127).spoken
            == "Note 1 on channel 1")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 17, lsb: 49, encoding: .absolute, first: 0, last: 9, min: 0, max: 9).spoken
            == "Control change 17 and 49 on channel 1, 14-bit, absolute")
        #expect(ControlFacts(kind: .cc, channel: 1, number: 6, encoding: .twosComplement, first: 1, last: 127, min: 1, max: 127).spoken
            == "Control change 6 on channel 1, relative, two's complement")
        #expect(ControlFacts(kind: .pitchBend, channel: 2, first: 0, last: 1, min: 0, max: 1).spoken == "Pitch bend on channel 2")
    }
}
