// The LC6000 jog display's SysEx protocol (#121, #165), as found and verified on hardware: Denon's frame, 21-bit
// numbers, the image as an MSB-first 7-bit bitstream, and the byte-sum the unit checks. The reference is
// tools/lc6000-display/jogbuild.py; the recipe is on #121.

/// The jog display protocol: the messages for the Controller port (hello, goodbye) and the WD port (upload, show).
public enum JogDisplay {
    /// Denon's SysEx header: manufacturer 00 02 0B, target 7F, device 10.
    static let head: [UInt8] = [0x00, 0x02, 0x0B, 0x7F, 0x10]

    /// One frame: F0, the header, the command, the payload's length in 14 bits, the payload, F7.
    public static func frame(_ command: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let count = payload.count
        return [0xF0] + head + [command, UInt8(count >> 7 & 0x7F), UInt8(count & 0x7F)] + payload + [0xF7]
    }

    /// A number up to 21 bits as three 7-bit bytes, most significant first.
    public static func u21(_ value: Int) -> [UInt8] {
        [UInt8(value >> 14 & 0x7F), UInt8(value >> 7 & 0x7F), UInt8(value & 0x7F)]
    }

    /// The bytes as an MSB-first bitstream cut into 7-bit bytes, the last one zero-padded: count × 8 / 7 + 1 bytes.
    public static func bits7(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 8 / 7 + 1)
        var accumulator = 0, bits = 0
        for byte in data {
            accumulator = (accumulator << 8 | Int(byte)) & 0x7FFF
            bits += 8
            while bits >= 7 {
                bits -= 7
                out.append(UInt8(accumulator >> bits & 0x7F))
            }
        }
        out.append(bits > 0 ? UInt8(accumulator << (7 - bits) & 0x7F) : 0)
        return out
    }

    /// 0E's payload: the slot, then the image's 32-bit byte-sum as 8 nibbles, most significant first. A wrong sum is
    /// refused (ack 06).
    public static func checksum(_ image: [UInt8], slot: UInt8) -> [UInt8] {
        let sum = image.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        return [slot] + stride(from: 28, through: 0, by: -4).map { UInt8(sum >> UInt32($0) & 0x0F) }
    }

    /// The host hello on the Controller port. Without it the unit refuses uploads (ack 06).
    public static let hello: [[UInt8]] = [
        [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x60, 0x00, 0x04, 0x04, 0x01, 0x01, 0x00, 0xF7],
        [0xF0, 0x00, 0x20, 0x7F, 0x01, 0xF7],
    ]

    /// The goodbye on the Controller port, at quit or unplug, so the unit returns to standalone.
    public static let goodbye: [UInt8] = [0xF0, 0x00, 0x20, 0x7F, 0x02, 0xF7]

    /// Shows the image in `slot` (0A, image index = slot).
    public static func show(slot: UInt8) -> [UInt8] {
        frame(0x0A, [0x01, 0x00, slot, 0x0D])
    }
}
