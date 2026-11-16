/// Syndicate's deck colors, as the app's deck badges draw them (#34). The platter ring shows its deck's color (#122).
///
/// One source of truth: the Presentation tests pin `DeckBadge`'s fills to `defaults`. A value, so a user setting can
/// replace the defaults later (#123): the Bridge reads its colors from its own `deckColors`.
/// How the ring (and a held pad) turns a color into the LC6000's 64 (#151): vivid keeps the hue; exact rounds each
/// channel, as the pad cue colors do.
public enum RingColors: String, Equatable, Sendable, Codable, CaseIterable {
    case vivid, exact
}

public struct DeckColors: Equatable, Sendable, Codable {
    /// [r, g, b] for decks 1-4.
    public var rgb: [Int: [Int]]

    public init(rgb: [Int: [Int]]) {
        self.rgb = rgb
    }

    /// Saved as four [r, g, b] arrays, deck 1 first.
    public init(from decoder: any Decoder) throws {
        let list = try decoder.singleValueContainer().decode([[Int]].self)
        rgb = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0.offset + 1, $0.element) })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode((1...4).map { rgb[$0] ?? [0, 0, 0] })
    }

    /// [r, g, b] for a deck, or nil for a deck outside 1-4.
    public subscript(deck: Int) -> [Int]? { rgb[deck] }

    /// The color as the LC6000 shows it, for Settings' preview swatch: the ring's rgb222 velocity, read back as RGB.
    public static func ledPreview(_ rgb: [Int]) -> [Int] {
        guard rgb.count == 3 else { return [0, 0, 0] }
        let velocity = Int(rgbToVelocity(rgb[0], rgb[1], rgb[2]))
        return [velocity >> 4 & 3, velocity >> 2 & 3, velocity & 3].map { $0 * 85 }
    }

    /// Whether the color is black, the one color the LC6000's ring can't show.
    public static func isBlack(_ rgb: some Collection<Int>) -> Bool { rgb.allSatisfy { $0 == 0 } }

    public static let defaults = DeckColors(rgb: [
        1: [0x6C, 0x72, 0x77],
        2: [0xEC, 0xCF, 0x65],
        3: [0xC5, 0x75, 0x4E],
        4: [0x62, 0x92, 0x9E],
    ])

    /// After a ColorPalette message ([slot, r, g, b]): the deck whose slot it is (slot 2N−1 is deck N) takes the color.
    /// Nil when the message isn't a deck's slot, so nothing needs repainting.
    public func updated(byPalette numbers: [Int]) -> DeckColors? {
        guard numbers.count >= 4, numbers[0] % 2 == 1, (1...7).contains(numbers[0]) else { return nil }
        let deck = (numbers[0] + 1) / 2
        var out = self
        // Black would turn the ring off: that deck keeps its default color.
        out.rgb[deck] = Self.isBlack(numbers[1...3]) ? Self.defaults[deck] : Array(numbers[1...3])
        return out == self ? nil : out
    }
}
