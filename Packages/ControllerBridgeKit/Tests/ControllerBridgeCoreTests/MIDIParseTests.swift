import Testing
import ControllerBridgeCore

@Suite struct MIDIParseTests {
    // UMP type 2, group 0, status 0x90 (note on, MIDI channel 1 = nibble 0), note 0x01, velocity 0x7F.
    @Test func noteOnOnChannelOne() {
        #expect(MIDIParse.events(words: [0x2090_017F]) == [.noteOn(channel: 0, note: 1, velocity: 127)])
    }

    // UMP type 2, status 0x80 (note off, channel 1), note 0x01, release velocity 0x00. Releases Cue/HotCue holds.
    @Test func noteOffOnChannelOne() {
        #expect(MIDIParse.events(words: [0x2080_0100]) == [.noteOff(channel: 0, note: 1, velocity: 0)])
    }

    // UMP type 2, status 0xB0 (control change, channel 1), controller 55 = 0x37 (jog), value 0x7F.
    @Test func controlChange55() {
        #expect(MIDIParse.events(words: [0x20B0_377F]) == [.controlChange(channel: 0, controller: 55, value: 127)])
    }

    // Pitch fader as a 14-bit pair: CC 8 (0x08) MSB = 0x40, then CC 40 (0x28) LSB = 0x01, in one packet.
    // Joining the pair is the Bridge's job, not the parser's.
    @Test func pitchPairInOnePacket() {
        #expect(MIDIParse.events(words: [0x20B0_0840, 0x20B0_2801]) == [
            .controlChange(channel: 0, controller: 8, value: 0x40),
            .controlChange(channel: 0, controller: 40, value: 0x01),
        ])
    }

    // UMP type 0xF (UMP stream, 128 bits = 4 words) is skipped whole; the note on after it still decodes.
    @Test func unknownTypeFIsSkipped() {
        #expect(MIDIParse.events(words: [0xF000_0000, 0x0000_0000, 0x0000_0000, 0x0000_0000, 0x2090_017F]) == [
            .noteOn(channel: 0, note: 1, velocity: 127),
        ])
    }

    // UMP type 2 with status 0xE0 (pitch bend, channel 1), LSB 0x00, MSB 0x40: not an event the Kit uses.
    @Test func otherVoiceStatusIsSkipped() {
        #expect(MIDIParse.events(words: [0x20E0_0040]) == [])
    }
}
