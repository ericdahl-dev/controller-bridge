import ControllerBridgeCapture
import Testing

/// CoreMIDI hands the app Universal MIDI Packets; the capture keeps MIDI 1.0 bytes (#186).
@Suite("Capture MIDI words")
struct CaptureMIDITests {
    @Test("Channel voice messages keep their length: three bytes, two for program change and channel pressure")
    func channelVoice() {
        #expect(CaptureMIDI.bytes(words: [0x2090_017F]) == [[0x90, 0x01, 0x7F]])
        #expect(CaptureMIDI.bytes(words: [0x2081_0100]) == [[0x81, 0x01, 0x00]])
        #expect(CaptureMIDI.bytes(words: [0x20B0_1140]) == [[0xB0, 0x11, 0x40]])
        #expect(CaptureMIDI.bytes(words: [0x20E1_0040]) == [[0xE1, 0x00, 0x40]])
        #expect(CaptureMIDI.bytes(words: [0x20C2_0500]) == [[0xC2, 0x05]])
        #expect(CaptureMIDI.bytes(words: [0x20D0_3000]) == [[0xD0, 0x30]])
    }

    @Test("System messages keep their own lengths: one byte for real-time, two or three for song position and select")
    func system() {
        #expect(CaptureMIDI.bytes(words: [0x10F8_0000]) == [[0xF8]])
        #expect(CaptureMIDI.bytes(words: [0x10FE_0000]) == [[0xFE]])
        #expect(CaptureMIDI.bytes(words: [0x10F2_1020]) == [[0xF2, 0x10, 0x20]])
        #expect(CaptureMIDI.bytes(words: [0x10F3_0400]) == [[0xF3, 0x04]])
        #expect(CaptureMIDI.bytes(words: [0x10F6_0000]) == [[0xF6]])
    }

    @Test("Several messages in a row, with SysEx (two words) skipped")
    func sequence() {
        let words: [UInt32] = [0x2090_017F, 0x3016_F000, 0x2010_0000, 0x10F8_0000, 0x2080_0100]
        #expect(CaptureMIDI.bytes(words: words) == [[0x90, 0x01, 0x7F], [0xF8], [0x80, 0x01, 0x00]])
    }
}
