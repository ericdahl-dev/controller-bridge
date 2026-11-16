/// Universal MIDI Packet words, as CoreMIDI delivers them, to the MIDI 1.0 bytes a capture keeps (#186).
public enum CaptureMIDI {
    /// Words per packet, by message type (the top nibble of the first word).
    private static let wordCount = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    /// Each MIDI 1.0 message in the words: channel voice (type 2) and system messages (type 1), at their own length.
    /// SysEx and MIDI 2.0 packets are skipped.
    public static func bytes(words: [UInt32]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = Int(word >> 28)
            let status = UInt8((word >> 16) & 0xFF), data1 = UInt8((word >> 8) & 0x7F), data2 = UInt8(word & 0x7F)
            let all = [status, data1, data2]
            switch type {
            case 1: messages.append(Array(all.prefix(systemLength(status))))
            case 2: messages.append(Array(all.prefix(status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0 ? 2 : 3)))
            default: break
            }
            index += wordCount[type]
        }
        return messages
    }

    /// A system message's length in bytes: song position 3; time code and song select 2; the rest 1.
    private static func systemLength(_ status: UInt8) -> Int {
        switch status {
        case 0xF2: 3
        case 0xF1, 0xF3: 2
        default: 1
        }
    }
}
