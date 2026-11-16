/// Decodes the 32-bit words of a CoreMIDI `MIDIEventPacket` (Universal MIDI Packets) into MIDI events.
///
/// Pure, so the CoreMIDI adapter's realtime callback only copies the words out and calls this.
public enum MIDIParse {
    /// UMP message length in 32-bit words, by message type (the top nibble of the first word).
    private static let wordCount: [Int] = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    public static func events(words: [UInt32]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var index = 0
        while index < words.count {
            let w = words[index]
            let type = Int(w >> 28)
            if type == 0x2 {
                let channel = UInt8((w >> 16) & 0x0F), data1 = UInt8((w >> 8) & 0x7F), data2 = UInt8(w & 0x7F)
                switch (w >> 20) & 0x0F {
                case 0x8: events.append(.noteOff(channel: channel, note: data1, velocity: data2))
                case 0xB: events.append(.controlChange(channel: channel, controller: data1, value: data2))
                case 0x9: events.append(.noteOn(channel: channel, note: data1, velocity: data2))
                default: break
                }
            }
            index += wordCount[type]
        }
        return events
    }
}

extension MIDIEvent {
    /// The same message on another channel (0-based).
    func onChannel(_ channel: UInt8) -> MIDIEvent {
        switch self {
        case .noteOn(_, let n, let v): .noteOn(channel: channel, note: n, velocity: v)
        case .noteOff(_, let n, let v): .noteOff(channel: channel, note: n, velocity: v)
        case .controlChange(_, let c, let v): .controlChange(channel: channel, controller: c, value: v)
        }
    }
}
