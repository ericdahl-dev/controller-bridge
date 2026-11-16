// Conversions from raw LC6000 MIDI values, shared by the control groups.

/// Signed ticks from an LC6000 relative CC value, per the LC6000 PRIME MIDI spec: 0x01-0x3F turn forward that many
/// ticks, 0x7F-0x40 turn back (0x7F is one tick back), and 0 is no movement.
func relativeTicks(_ value: UInt8) -> Int {
    let value = Int(value & 0x7F)
    return value < 0x40 ? value : value - 0x80
}

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
