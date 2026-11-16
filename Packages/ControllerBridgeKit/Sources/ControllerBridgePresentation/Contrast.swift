import Foundation

/// An sRGB color, 8 bits per channel.
public struct RGB: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }
}

public enum Contrast {
    /// The WCAG 2.x contrast ratio, 1...21, whichever color is lighter.
    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG relative luminance of an sRGB color.
    static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}
