/// The colored square behind a deck number, as Syndicate draws it. Wherever the bridge shows a deck, it uses this.
public struct DeckBadge: Equatable, Sendable {
    public var fill: RGB
    public var digit: RGB

    public init(fill: RGB, digit: RGB) {
        self.fill = fill
        self.digit = digit
    }

    /// A badge on any fill, such as a deck color from Syndicate's palette (#123), with the more legible digit.
    public init(fill: RGB) {
        self.init(fill: fill, digit: Self.legibleDigit(on: fill))
    }

    public init(deck: Int) {
        let fill = Self.fills[deck] ?? Self.neutral
        self.init(fill: fill, digit: Self.legibleDigit(on: fill))
    }

    /// Sampled from Syndicate's deck headers.
    static let fills: [Int: RGB] = [
        1: RGB(hex: 0x6C7277),
        2: RGB(hex: 0xECCF65),
        3: RGB(hex: 0xC5754E),
        4: RGB(hex: 0x62929E),
    ]

    /// A deck outside 1-4. Badge colors are deck colors, not theme surfaces, so they don't change with the theme
    /// (#127).
    static let neutral = RGB(hex: 0x424242)

    static let white = RGB(hex: 0xFFFFFF)

    /// The near-black digit, fixed rather than the theme's background, so the digit rule holds in either theme (#127).
    static let nearBlack = RGB(hex: 0x141415)

    static let black = RGB(hex: 0x000000)

    /// White or a near-black, whichever has more contrast on `fill`. On a mid tone where neither
    /// reaches 4.5:1, pure black does: white or black always reaches about 4.58:1 (#123).
    static func legibleDigit(on fill: RGB) -> RGB {
        let best = Contrast.ratio(white, fill) >= Contrast.ratio(nearBlack, fill) ? white : nearBlack
        if Contrast.ratio(best, fill) >= 4.5 { return best }
        return Contrast.ratio(white, fill) >= Contrast.ratio(black, fill) ? white : black
    }
}
