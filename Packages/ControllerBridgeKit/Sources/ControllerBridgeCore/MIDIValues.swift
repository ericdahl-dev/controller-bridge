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
