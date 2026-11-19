// The drawn display's phase rule (#462): a deck's PhaseOffset as the value op 0B carries.

/// One deck's phase value for the wire.
struct DrawnPhase {
    /// Op 0B's unknown: not playing, or no offset since the deck loaded.
    static let unknown = -8192
    /// In phase is entered under `enter` beats and left only over `leave`, so the tick doesn't flicker at the edge.
    static let enter = 0.002, leave = 0.004

    private var inPhase = false

    /// The value to send for the deck's latest offset in beats.
    mutating func value(offset: Double?, playing: Bool) -> Int {
        guard playing, let offset, offset.isFinite else {
            inPhase = false
            return Self.unknown
        }
        inPhase = inPhase ? abs(offset) <= Self.leave : abs(offset) < Self.enter
        if inPhase { return 0 }
        return Int(min(max((offset * 16384).rounded(), -8191), 8191))
    }
}
