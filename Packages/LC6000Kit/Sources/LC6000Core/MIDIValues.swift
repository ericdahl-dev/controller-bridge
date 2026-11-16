// Conversions from raw LC6000 MIDI values, shared by the control groups.

/// Signed ticks from an LC6000 relative CC value, per the LC6000 PRIME MIDI spec: 0x01-0x3F turn forward that many
/// ticks, 0x7F-0x40 turn back (0x7F is one tick back), and 0 is no movement.
func relativeTicks(_ value: UInt8) -> Int {
    let value = Int(value & 0x7F)
    return value < 0x40 ? value : value - 0x80
}

/// An LC6000 pad or ring color velocity for an 8-bit RGB color.
///
/// PROVISIONAL (check with the LED sweep): the 64-entry color table, velocities 0x00-0x3F, is 2 bits per channel
/// laid out 0b00RRGGBB. A dim color that rounds to black lights its brightest channel at the lowest level instead,
/// so a cue is never dark by accident. Ties go to red, then green, as in the Python bridge.
func rgbToVelocity(_ red: Int, _ green: Int, _ blue: Int) -> UInt8 {
    func level(_ channel: Int) -> Int { max(0, min(3, Int((Double(channel) / 255 * 3).rounded()))) }
    let velocity = level(red) << 4 | level(green) << 2 | level(blue)
    guard velocity == 0, red > 0 || green > 0 || blue > 0 else { return UInt8(velocity) }
    if red >= green, red >= blue { return 1 << 4 }
    return green >= blue ? 1 << 2 : 1
}
