/// LC6000 PRIME traffic for the capture tests, as (seconds, bytes).
///
/// HAND-BUILT, REPLACE WITH RECORDING: these are written from the hardware-confirmed LC6000 facts (the bundled profile
/// and #12, #121, #165), not recorded. A listen-only recording of the same gestures replaces them in a follow-up.
/// No djay traffic is used.
enum LC6000Traffic {
    typealias Take = [(time: Double, bytes: [UInt8])]

    /// The host-mode heartbeat: note 52 (0x34), here on channels 1 and 2, every half second.
    static func heartbeat(from start: Double, count: Int) -> Take {
        (0..<count).flatMap { i -> Take in
            let time = start + Double(i) * 0.5
            return [(time, [0x90, 0x34, 0x7F]), (time + 0.001, [0x91, 0x34, 0x7F])]
        }
    }

    /// Play on deck 1: note 1, channel 1, released with a note-off.
    static let play: Take = [(0.00, [0x90, 0x01, 0x7F]), (0.12, [0x80, 0x01, 0x00])]

    /// Cue on deck 1: note 2.
    static let cue: Take = [(0.00, [0x90, 0x02, 0x7F]), (0.15, [0x80, 0x02, 0x00])]

    /// Shift (note 26) held while Play is pressed. The LC6000 sends Play unchanged; the bridge tracks Shift itself.
    static let shiftPlay: Take = [
        (0.0, [0x90, 26, 0x7F]), (0.3, [0x90, 0x01, 0x7F]), (0.4, [0x80, 0x01, 0x00]), (0.6, [0x80, 26, 0x00]),
    ]

    /// The jog wheel's edge spun forward: a 14-bit position on CC 17 (MSB) and CC 49 (LSB), 8000 to 8200.
    static let jogSpin: Take = pairs(msb: 17, lsb: 49, values: Array(stride(from: 8000, through: 8200, by: 40)))

    /// Needle Drop slid left to right: a 14-bit position on CC 64 (MSB) and CC 65 (LSB). Not an n / n+32 pair.
    static let needleSlide: Take = pairs(msb: 64, lsb: 65, values: [0, 4096, 8192, 12288, 16383])

    /// The jog's top touched and turned: platter-touch note 40 around the 14-bit position on CC 17/49.
    static let jogTouchTurn: Take = [(0.0, [0x90, 40, 0x7F])] + pairs(msb: 17, lsb: 49, values: [100, 140, 180]).map { ($0.time + 0.05, $0.bytes) }
        + [(0.2, [0x80, 40, 0x00])]

    /// Needle Drop touched and slid: touch note 70 around the 14-bit position on CC 64/65.
    static let needleTouchSlide: Take = [(0.0, [0x90, 70, 0x7F])] + pairs(msb: 64, lsb: 65, values: [2000, 9000]).map { ($0.time + 0.05, $0.bytes) }
        + [(0.2, [0x80, 70, 0x00])]

    /// The pitch fader moved from the bottom to the top: CC 8 (MSB) and CC 40 (LSB), 16383 down to 0, since up is 0.
    static let pitchUp: Take = pairs(msb: 8, lsb: 40, values: [16383, 12288, 8192, 4096, 0])

    /// The browse knob turned right three clicks, then left two: CC 6, two's complement (0x01 forward, 0x7F back).
    static let browseTurn: Take = cc(6, [0x01, 0x01, 0x01, 0x7F, 0x7F])

    /// One CC on channel 1, 50 ms apart.
    static func cc(_ number: UInt8, _ values: [UInt8], channel: UInt8 = 0) -> Take {
        values.enumerated().map { (Double($0) * 0.05, [0xB0 | channel, number, $1]) }
    }

    /// A 14-bit value as MSB then LSB on channel 1, 10 ms apart.
    static func pairs(msb: UInt8, lsb: UInt8, values: [Int], channel: UInt8 = 0) -> Take {
        values.enumerated().flatMap { index, value -> Take in
            let time = Double(index) * 0.01
            return [(time, [0xB0 | channel, msb, UInt8(value >> 7)]), (time + 0.001, [0xB0 | channel, lsb, UInt8(value & 0x7F)])]
        }
    }
}

/// Other controllers' shapes the LC6000 doesn't send, so the inference is covered both ways. Hand-built.
enum OtherTraffic {
    /// A button released with a note-on at velocity 0, as many controllers do.
    /// A 7-bit knob turned from 10 to 20 on CC 22, channel 2.
    static let knob: [(time: Double, bytes: [UInt8])] = (10...20).map { (Double($0) * 0.01, [0xB1, 22, UInt8($0)]) }

    /// Encoders turned right twice, then left twice, in the other relative formats.
    static let offset64Turn = LC6000Traffic.cc(30, [0x41, 0x41, 0x3F, 0x3F])
    static let signMagnitudeTurn = LC6000Traffic.cc(30, [0x01, 0x02, 0x41, 0x41])

    /// An encoder turned one way only, 0x41 each click: offset-64 forward or sign-magnitude back, so it can't be told.
    static let oneWayTurn = LC6000Traffic.cc(30, [0x41, 0x41, 0x41])

    /// A pitch fader on pitch bend, channel 2, moved from the middle to the top: 14-bit, LSB first on the wire.
    static let pitchBend: [(time: Double, bytes: [UInt8])] = [8192, 12288, 16383].enumerated().map {
        (Double($0) * 0.01, [0xE1, UInt8($1 & 0x7F), UInt8($1 >> 7)])
    }

    /// A controller whose Shift (note 63, channel 1) moves Play from note 11 to note 75 on the same channel.
    static let play: [(time: Double, bytes: [UInt8])] = [(0.0, [0x90, 11, 0x7F]), (0.1, [0x80, 11, 0x00])]
    static let shiftPlay: [(time: Double, bytes: [UInt8])] = [
        (0.0, [0x90, 63, 0x7F]), (0.3, [0x90, 75, 0x7F]), (0.4, [0x80, 75, 0x00]), (0.6, [0x80, 63, 0x00]),
    ]

    static let noteOnZeroRelease: [(time: Double, bytes: [UInt8])] = [(0.00, [0x92, 0x0B, 0x7F]), (0.10, [0x92, 0x0B, 0x00])]
}
