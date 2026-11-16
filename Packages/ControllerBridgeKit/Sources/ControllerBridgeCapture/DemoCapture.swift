/// The demo controller in the capture window (#186): a fixed, LC6000-like answer to each prompt of the standard list,
/// so the window can be tried and reviewed without hardware. The app feeds it through the same flow as real MIDI.
/// It includes the LC6000's note 52 heartbeat, so the idle step has something to learn.
public enum DemoCapture {
    public typealias Take = [(time: Double, bytes: [UInt8])]

    /// The name the demo controller shows under (the same as the bridge's demo controller, #64).
    public static let deviceName = "Demo controller"
    public static let ports = CapturePorts(input: [deviceName], output: [deviceName])

    /// What the demo controller sends for a prompt, in seconds from when it starts.
    public static func take(for prompt: CapturePrompt) -> Take {
        let heartbeat: Take = [(0.0, [0x90, 0x34, 0x7F]), (0.5, [0x90, 0x34, 0x7F]), (1.0, [0x90, 0x34, 0x7F])]
        if prompt.gesture == .idle { return heartbeat + [(1.5, [0x90, 0x34, 0x7F]), (2.0, [0x90, 0x34, 0x7F])] }
        return (heartbeat + controls(for: prompt)).sorted { $0.time < $1.time }
    }

    private static let notes: [String: UInt8] = [
        "deck1.play": 1, "deck1.cue": 2, "deck1.sync": 20, "deck1.loop_in": 8, "deck1.loop_out": 9,
        "deck1.auto_loop": 10, "deck1.browse.press": 18, "deck1.shift": 26,
        "deck1.hotcue1": 32, "deck1.hotcue2": 33, "deck1.hotcue3": 34, "deck1.hotcue4": 35,
        "deck1.hotcue5": 36, "deck1.hotcue6": 37, "deck1.hotcue7": 38, "deck1.hotcue8": 39,
    ]

    private static func controls(for prompt: CapturePrompt) -> Take {
        switch prompt.id {
        case "deck1.pitch": return pairs(msb: 8, lsb: 40, values: stride(from: 0, through: 16383, by: 2048).map { $0 } + [16383])
        case "deck1.jog.touch": return held(40, around: pairs(msb: 17, lsb: 49, values: [8000, 8100, 8200, 8100, 8000]))
        case "deck1.jog.edge": return pairs(msb: 17, lsb: 49, values: [8000, 8200, 8400, 8200])
        case "deck1.needle": return held(70, around: pairs(msb: 64, lsb: 65, values: [1000, 6000, 11000, 15000]))
        case "deck1.browse.turn":
            return [0x01, 0x01, 0x01, 0x7F, 0x7F, 0x7F].enumerated().map { (0.3 + Double($0) * 0.15, [0xB0, 6, $1]) }
        // The LC6000's Shift + deck select (ch16 note 55), then note 51 at 0 on the old channel and 127 on the new (#217).
        case "layer2.select":
            return held(26, around: [(0.3, [0x9F, 55, 0x7F]), (0.4, [0x8F, 55, 0x00]), (0.45, [0x90, 51, 0x00]), (0.46, [0x91, 51, 0x7F])])
        case "deck2.play": return press(1, channel: 1)
        default:
            if let base = prompt.shiftedOf, let note = notes[base] { return held(26, around: press(note).map { ($0.time + 0.2, $0.bytes) }) }
            return press(notes[prompt.id] ?? 100)
        }
    }

    private static func press(_ note: UInt8, channel: UInt8 = 0) -> Take {
        [(0.3, [0x90 | channel, note, 0x7F]), (0.45, [0x80 | channel, note, 0x00])]
    }

    /// `note` pressed before the take and let go after it, like a touch or Shift.
    private static func held(_ note: UInt8, around take: Take) -> Take {
        let end = (take.last?.time ?? 0) + 0.1
        return [(0.2, [0x90, note, 0x7F])] + take.map { ($0.time + 0.3, $0.bytes) } + [(end + 0.3, [0x80, note, 0x00])]
    }

    /// 14-bit values as MSB then LSB on channel 1, 50 ms apart.
    private static func pairs(msb: UInt8, lsb: UInt8, values: [Int]) -> Take {
        values.enumerated().flatMap { index, value -> Take in
            let time = 0.3 + Double(index) * 0.05
            return [(time, [0xB0, msb, UInt8(value >> 7)]), (time + 0.001, [0xB0, lsb, UInt8(value & 0x7F)])]
        }
    }
}
