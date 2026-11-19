// Track time on the drawn jog display (#460): how the last minute's warning looks now. The renderer draws it; the
// display firmware's C keeps the same rules.

public enum JogTrackTime {
    /// The warning covers this many seconds before the end.
    public static let warningSeconds = 60
    /// The warning's red, 0xFF3B30, and its hue in degrees.
    public static let warningRed = [0xFF, 0x3B, 0x30]
    static let warningHue = 3.5
    /// A deck colour within this many degrees of the red's hue, and saturated, counts as near red.
    static let nearRedHue = 25.0
    /// The text's white, 0xEDEDEA: the warning's normal fill for a deck near red.
    static let white = [0xED, 0xED, 0xEA]

    public enum Look: Equatable, Sendable {
        /// No warning: the text white, the ring the deck colour.
        case normal
        /// The warning's red half: text and ring fill red.
        case warningRed
        /// The warning's other half: text white, ring `warningNormalFill`.
        case warningNormal
    }

    /// Playing, a known length and `warningSeconds` or less left: a 1 Hz blink. `phase` is the time since the shown
    /// second last changed (0 to 1), so red starts on the frame the digit changes.
    public static func look(elapsed: Int, length: Int, playing: Bool, phase: Double) -> Look {
        guard playing, length > 0, length - elapsed <= warningSeconds else { return .normal }
        return phase < 0.5 ? .warningRed : .warningNormal
    }

    /// The ring's fill in the warning's normal half: the deck colour, or white when that is near red, so the blink
    /// still shows. Near red: the channels' spread at least half the brightest, and the hue within `nearRedHue`.
    public static func warningNormalFill(deck: [Int]) -> [Int] {
        guard deck.count == 3 else { return deck }
        let r = Double(deck[0]), g = Double(deck[1]), b = Double(deck[2])
        let high = max(r, g, b), spread = high - min(r, g, b)
        guard high > 0, spread >= high / 2 else { return deck }
        var hue: Double
        if high == r { hue = 60 * (g - b) / spread } else if high == g { hue = 60 * (2 + (b - r) / spread) }
        else { hue = 60 * (4 + (r - g) / spread) }
        if hue < 0 { hue += 360 }
        let distance = min(abs(hue - warningHue), 360 - abs(hue - warningHue))
        return distance <= nearRedHue ? white : deck
    }
}
