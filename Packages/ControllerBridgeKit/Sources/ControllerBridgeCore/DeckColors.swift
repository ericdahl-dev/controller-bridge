/// Syndicate's deck colors, as the app's deck badges draw them (#34). The platter ring shows its deck's color (#122).
/// The one source of truth: the Presentation tests pin `DeckBadge`'s fills to these values.
public enum DeckColors {
    /// [r, g, b] for decks 1-4.
    public static let rgb: [Int: [Int]] = [
        1: [0x6C, 0x72, 0x77],
        2: [0xEC, 0xCF, 0x65],
        3: [0xC5, 0x75, 0x4E],
        4: [0x62, 0x92, 0x9E],
    ]
}
