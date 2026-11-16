import CoreGraphics
import Foundation
import ImageIO
@testable import ControllerBridgeCore
import Testing

/// The jog display's PNG (#121, #165): rotated 180°, in the layout the unit has accepted (IHDR, sRGB, eXIf, IDAT in
/// 16,384-byte pieces, IEND). Checks: the published CRC-32 and Adler-32 check values, the fixed chunks' bytes, and
/// ImageIO reading the pixels back.
@Suite("Jog image PNG")
struct JogImageTests {
    @Test("CRC-32 and Adler-32 match their published check values")
    func checksums() {
        #expect(JogImage.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(JogImage.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
    }

    /// A 2×2 RGBA image: red, green / blue, white.
    static let pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]

    @Test("The fixed chunks: the signature, IHDR (2×2, 8-bit RGBA), sRGB, eXIf with the dimensions, and IEND last")
    func layout() {
        let png = JogImage.png(rgba: Self.pixels, width: 2, height: 2)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(Array(png[8..<33]) == [0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
                                       0x08, 0x06, 0x00, 0x00, 0x00, 0x72, 0xB6, 0x0D, 0x24])
        #expect(Array(png[33..<46]) == [0x00, 0x00, 0x00, 0x01, 0x73, 0x52, 0x47, 0x42, 0x00, 0xAE, 0xCE, 0x1C, 0xE9])
        #expect(Array(png[46..<54]) == [0x00, 0x00, 0x00, 0x38, 0x65, 0x58, 0x49, 0x66])
        #expect(Array(png[(png.count - 12)...]) == [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    @Test("ImageIO reads the pixels back as they were")
    func readsBack() throws {
        let png = JogImage.png(rgba: Self.pixels, width: 2, height: 2)
        #expect(try Self.decode(png) == Self.pixels)
    }

    @Test("For the unit, the image is turned 180°: white, blue / green, red")
    func rotated() throws {
        let png = JogImage.forUnit(rgba: Self.pixels, width: 2, height: 2)
        #expect(try Self.decode(png) == [255, 255, 255, 255, 0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255])
    }

    @Test("A big image's data goes in IDAT pieces of at most 16,384 bytes")
    func idatPieces() throws {
        // Noise doesn't compress, so 198×198 RGBA needs several pieces.
        var state: UInt32 = 165
        // Opaque, so reading back (premultiplied) gives the same bytes.
        let noise = (0..<198 * 198 * 4).map { index -> UInt8 in
            state = state &* 1_664_525 &+ 1_013_904_223
            return index % 4 == 3 ? 255 : UInt8(state >> 24)
        }
        let png = JogImage.png(rgba: noise, width: 198, height: 198)
        var lengths: [Int] = [], pos = 8
        while pos < png.count {
            let length = png[pos..<pos + 4].reduce(0) { $0 << 8 | Int($1) }
            if Array(png[pos + 4..<pos + 8]) == Array("IDAT".utf8) { lengths.append(length) }
            pos += 12 + length
        }
        #expect(lengths.count > 1)
        #expect(lengths.dropLast().allSatisfy { $0 == 16384 })
        #expect(try Self.decode(png) == noise)
    }

    static func decode(_ png: [UInt8]) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(Data(png) as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return out
    }
}
