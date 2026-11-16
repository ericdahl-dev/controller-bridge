// Conversions from raw LC6000 MIDI values, shared by the control groups.

/// An LC6000 pad or ring color velocity for an 8-bit RGB color.
///
/// The 64-entry color table, velocities 0x00-0x3F, is 2 bits per channel laid out 0b00RRGGBB, confirmed on a real
/// LC6000 (2026-11-15, #12: 48 red, 12 green, 3 blue, 63 white). A dim color that rounds to black lights its brightest channel at the lowest level instead,
/// so a cue is never dark by accident. Ties go to red, then green, as in the Python bridge.
func rgbToVelocity(_ red: Int, _ green: Int, _ blue: Int) -> UInt8 {
    func level(_ channel: Int) -> Int { max(0, min(3, Int((Double(channel) / 255 * 3).rounded()))) }
    let velocity = level(red) << 4 | level(green) << 2 | level(blue)
    guard velocity == 0, red > 0 || green > 0 || blue > 0 else { return UInt8(velocity) }
    if red >= green, red >= blue { return 1 << 4 }
    return green >= blue ? 1 << 2 : 1
}

/// A double-precision CC pair as 0...16383.
func join14Bit(msb: UInt8, lsb: UInt8) -> Int {
    Int(msb & 0x7F) << 7 | Int(lsb & 0x7F)
}

/// A 14-bit pitch fader position as Syndicate's TempoSlider, -1...+1. Within `deadZone` of the center it snaps to 0.
func tempoSlider(from value14: Int, invert: Bool, deadZone: Double) -> Double {
    var t = Double(value14) / 16383 * 2 - 1
    if invert { t = -t }
    if abs(t) < deadZone { t = 0 }
    return min(1, max(-1, t))
}

/// A 7-bit pitch fader's value as Syndicate's TempoSlider, -1...+1 (#195). 64 is the exact center, so a centered
/// fader reads 0: below it each step is 1/64, above it 1/63, so 0 and 127 reach the ends.
func tempoSlider(from7Bit value: UInt8, invert: Bool, deadZone: Double) -> Double {
    let v = Double(value & 0x7F) - 64
    var t = v < 0 ? v / 64 : v / 63
    if invert { t = -t }
    if abs(t) < deadZone { t = 0 }
    return min(1, max(-1, t))
}

/// A vivid LC6000 color velocity that keeps the hue (#151), for the platter ring and a held pad. rgb222 rounding on
/// its own lands a color's weaker channels on level 1-2, which adds white and washes the color out on the unit. So:
/// take out the white (the smallest channel), scale the strongest channel to level 3, drop any channel under 30 % of
/// it, then quantize. A near-gray (saturation under 20 %) has no hue to keep and uses the exact mapping.
func vividVelocity(_ red: Int, _ green: Int, _ blue: Int) -> UInt8 {
    let rgb = [red, green, blue].map { max(0, min(255, $0)) }
    let top = rgb.max() ?? 0, bottom = rgb.min() ?? 0
    guard top > 0, Double(top - bottom) / Double(top) >= 0.2 else { return rgbToVelocity(red, green, blue) }
    let levels = rgb.map { channel -> Int in
        let share = Double(channel - bottom) / Double(top - bottom)
        return share < 0.3 ? 0 : Int((share * 3).rounded())
    }
    return UInt8(levels[0] << 4 | levels[1] << 2 | levels[2])
}

/// How a controller's relative encoders (a browse knob, a loop-size knob) write a turn into one CC value (#193).
public enum EncoderFormat: String, CaseIterable, Equatable, Sendable, Codable {
    /// The LC6000's: 0x01-0x3F turn forward that many ticks, 0x7F-0x40 turn back (0x7F is one tick back).
    case twosComplement = "twos_complement"
    /// 0x40 is no movement; above it turns forward, below it back.
    case offset64 = "offset_64"
    /// Bit 6 is the direction (set is back), the low six bits how far; 0x40 is a minus zero.
    case signMagnitude = "sign_magnitude"

    /// Signed ticks for one CC value.
    public func ticks(_ value: UInt8) -> Int {
        let value = Int(value & 0x7F)
        switch self {
        case .twosComplement: return value < 0x40 ? value : value - 0x80
        case .offset64: return value - 0x40
        case .signMagnitude: return value & 0x40 == 0 ? value : -(value & 0x3F)
        }
    }

    /// The CC value that turns by `ticks` (clamped to what one value can say), for the demo controller (#204).
    public func value(forTicks ticks: Int) -> UInt8 {
        switch self {
        case .twosComplement: return UInt8(max(-64, min(63, ticks)) & 0x7F)
        case .offset64: return UInt8(max(0, min(127, ticks + 0x40)))
        case .signMagnitude: return ticks < 0 ? UInt8(0x40 | min(63, -ticks)) : UInt8(min(63, ticks))
        }
    }
}

/// How a controller turns a color into a pad or ring velocity (#197).
public enum ColorTable: Equatable, Sendable {
    /// The LC6000's 64 colors: 2 bits per channel, 0b00RRGGBB.
    case rgb222
    /// Explicit entries; a color takes the nearest entry's value.
    case list([Entry])

    public struct Entry: Equatable, Sendable, Codable {
        public var rgb: [Int]
        public var value: Int

        public init(rgb: [Int], value: Int) {
            self.rgb = rgb
            self.value = value
        }
    }

    /// The velocity for an [r, g, b] color. Black is off. A dim color that would land on black lights instead: rgb222
    /// at its strongest channel's lowest level, a list at the nearest entry that isn't black.
    public func velocity(for rgb: [Int]) -> UInt8 {
        guard rgb.count == 3 else { return 0 }
        switch self {
        case .rgb222: return rgbToVelocity(rgb[0], rgb[1], rgb[2])
        case .list(let entries): return Self.nearest(rgb, in: entries)
        }
    }

    /// The vivid velocity (#151) for the ring and a held pad: the LC6000's own on rgb222; on a list, the vivid color's
    /// nearest entry.
    public func vivid(for rgb: [Int]) -> UInt8 {
        guard rgb.count == 3 else { return 0 }
        switch self {
        case .rgb222: return vividVelocity(rgb[0], rgb[1], rgb[2])
        case .list(let entries):
            let v = vividVelocity(rgb[0], rgb[1], rgb[2])
            return Self.nearest([Int(v) >> 4 & 3, Int(v) >> 2 & 3, Int(v) & 3].map { $0 * 85 }, in: entries)
        }
    }

    private static func nearest(_ rgb: [Int], in entries: [Entry]) -> UInt8 {
        let isBlack = { (color: [Int]) in color.allSatisfy { $0 == 0 } }
        if isBlack(rgb) { return 0 }
        func distance(_ entry: Entry) -> Int {
            zip(rgb, entry.rgb).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
        }
        // The first of equally near entries wins.
        let ordered = entries.filter { $0.rgb.count == 3 }
        guard let best = ordered.min(by: { distance($0) < distance($1) }) else { return 0 }
        guard isBlack(best.rgb) else { return UInt8(clamping: best.value) }
        // Dim fallback: a color shouldn't go dark by rounding.
        return ordered.filter { !isBlack($0.rgb) }.min(by: { distance($0) < distance($1) }).map { UInt8(clamping: $0.value) } ?? 0
    }
}
