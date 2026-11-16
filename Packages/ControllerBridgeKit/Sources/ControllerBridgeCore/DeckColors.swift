/// Syndicate's deck colors, as the app's deck badges draw them (#34). The platter ring shows its deck's color (#122).
///
/// One source of truth: the Presentation tests pin `DeckBadge`'s fills to `defaults`. A value, so a user setting can
/// replace the defaults later (#123): the Bridge reads its colors from its own `deckColors`.
public struct DeckColors: Equatable, Sendable {
    /// [r, g, b] for decks 1-4.
    public var rgb: [Int: [Int]]

    public init(rgb: [Int: [Int]]) {
        self.rgb = rgb
    }

    /// [r, g, b] for a deck, or nil for a deck outside 1-4.
    public subscript(deck: Int) -> [Int]? { rgb[deck] }

    public static let defaults = DeckColors(rgb: [
        1: [0x6C, 0x72, 0x77],
        2: [0xEC, 0xCF, 0x65],
        3: [0xC5, 0x75, 0x4E],
        4: [0x62, 0x92, 0x9E],
    ])
}
