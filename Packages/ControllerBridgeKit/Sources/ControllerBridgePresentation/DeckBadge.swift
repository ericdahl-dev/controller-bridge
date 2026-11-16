/// The colored square behind a deck number, as Syndicate draws it. Wherever the bridge shows a deck, it uses this.
public struct DeckBadge: Equatable, Sendable {
    public var fill: RGB
    public var digit: RGB

    public init(fill: RGB, digit: RGB) {
        self.fill = fill
        self.digit = digit
    }

    public init(deck: Int) {
        let fill = Self.fills[deck] ?? Palette.buttonRaised
        self.init(fill: fill, digit: Self.legibleDigit(on: fill))
    }

    /// Sampled from Syndicate's deck headers.
    static let fills: [Int: RGB] = [
        1: RGB(hex: 0x6C7277),
        2: RGB(hex: 0xECCF65),
        3: RGB(hex: 0xC5754E),
        4: RGB(hex: 0x62929E),
    ]

    static let white = RGB(hex: 0xFFFFFF)

    /// White or the background's near-black, whichever has more contrast on `fill`.
    static func legibleDigit(on fill: RGB) -> RGB {
        Contrast.ratio(white, fill) >= Contrast.ratio(Palette.background, fill) ? white : Palette.background
    }
}
