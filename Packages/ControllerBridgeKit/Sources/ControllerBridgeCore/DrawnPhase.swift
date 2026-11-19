// The drawn display's phase rule (#462): a deck's PhaseOffset as the value op 0B carries.

/// One deck's phase value for the wire.
struct DrawnPhase {
    /// Op 0B's unknown: not playing, or no offset since the deck loaded.
    static let unknown = -8192

    /// The value to send for the deck's latest offset in beats.
    mutating func value(offset: Double?, playing: Bool) -> Int {
        guard playing, let offset, offset.isFinite else { return Self.unknown }
        return Int(min(max((offset * 16384).rounded(), -8191), 8191))
    }
}
