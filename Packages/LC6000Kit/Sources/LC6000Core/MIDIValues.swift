// Conversions from raw LC6000 MIDI values, shared by the control groups.

/// Signed ticks from an LC6000 relative CC value, per the LC6000 PRIME MIDI spec: 0x01-0x3F turn forward that many
/// ticks, 0x7F-0x40 turn back (0x7F is one tick back), and 0 is no movement.
func relativeTicks(_ value: UInt8) -> Int {
    let value = Int(value & 0x7F)
    return value < 0x40 ? value : value - 0x80
}
