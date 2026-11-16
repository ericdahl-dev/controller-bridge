// The jog display's PNG (#121, #165): an RGBA image turned 180° (the unit shows uploads upside down) and written in
// the layout the unit has accepted, as tools/lc6000-display/jogbuild.py writes it: the signature, IHDR, sRGB, eXIf
// with the dimensions, the zlib stream in IDAT pieces of at most 16,384 bytes, then IEND. Row filter 0.
import Compression
import Foundation

public enum JogImage {
    /// The display's size in pixels.
    public static let size = 198

    /// The PNG to upload: `rgba` (row by row, top first) turned 180°.
    public static func forUnit(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        png(rgba: rotated180(rgba, width: width, height: height), width: width, height: height)
    }

    /// The pixels turned half way round: the last pixel first.
    static func rotated180(_ rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: rgba.count)
        let count = width * height
        for index in 0..<count {
            let from = index * 4, to = (count - 1 - index) * 4
            out[to..<to + 4] = rgba[from..<from + 4]
        }
        return out
    }

    /// An 8-bit RGBA PNG in the unit's layout.
    public static func png(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        var raw: [UInt8] = []
        raw.reserveCapacity((width * 4 + 1) * height)
        for row in 0..<height {
            raw.append(0)
            raw += rgba[row * width * 4..<(row + 1) * width * 4]
        }
        let data = zlib(raw)
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be32(width) + be32(height) + [8, 6, 0, 0, 0])
        out += chunk("sRGB", [0])
        out += chunk("eXIf", exifDimensions(width: width, height: height))
        for start in stride(from: 0, to: data.count, by: 16384) {
            out += chunk("IDAT", Array(data[start..<min(start + 16384, data.count)]))
        }
        return out + chunk("IEND", [])
    }

    static func be32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func chunk(_ kind: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(kind.utf8) + body
        return be32(body.count) + typed + be32(Int(crc32(typed)))
    }

    /// A minimal eXIf, as on the files the unit accepted: a big-endian TIFF header, an Exif IFD pointer, and the
    /// PixelXDimension and PixelYDimension tags.
    static func exifDimensions(width: Int, height: Int) -> [UInt8] {
        let tiff: [UInt8] = [0x4D, 0x4D, 0x00, 0x2A] + be32(8)
        let ifd0: [UInt8] = [0x00, 0x01, 0x87, 0x69, 0x00, 0x04] + be32(1) + be32(26) + be32(0)
        let exif: [UInt8] = [0x00, 0x02, 0xA0, 0x02, 0x00, 0x04] + be32(1) + be32(width)
            + [0xA0, 0x03, 0x00, 0x04] + be32(1) + be32(height)
        return tiff + ifd0 + exif + be32(0)
    }

    /// A zlib stream: a header, the raw deflate data from the Compression framework, and the Adler-32 of the input.
    static func zlib(_ input: [UInt8]) -> [UInt8] {
        let capacity = input.count + input.count / 10 + 1024
        var deflated = [UInt8](repeating: 0, count: capacity)
        let written = input.withUnsafeBufferPointer { source in
            compression_encode_buffer(&deflated, capacity, source.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
        }
        return [0x78, 0x01] + deflated.prefix(written) + be32(Int(adler32(input)))
    }

    static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        ~bytes.reduce(UInt32.max) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }
}
