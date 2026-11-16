/// The bridge's colors, sampled from Syndicate's public screenshots (untitledaudiosyndicate.com/product/*.webp) and
/// adjusted only where WCAG AA needs it. Dark only: there is no light theme.
public enum Palette {
    // Surfaces, darkest first.
    public static let background = RGB(hex: 0x141415)
    public static let panel = RGB(hex: 0x1D1D1E)
    public static let button = RGB(hex: 0x2A2A2A)
    public static let buttonRaised = RGB(hex: 0x424242)
    public static let hairline = RGB(hex: 0x393939)
    /// A button's edge: the lightest gray that still reads at 3:1 on both the panel and the button fill (#67).
    public static let buttonEdge = RGB(hex: 0x747474)
    /// The bar under a selected tab or deck: the second, non-color cue for "selected" (#67).
    public static let selectedBar = RGB(hex: 0xD5D5D5)

    // Text.
    public static let text = RGB(hex: 0xD5D5D5)
    public static let caption = RGB(hex: 0xA9AAAA)

    // State. Each is always paired with a word, never shown by color alone.
    public static let live = RGB(hex: 0x72CD8B)
    public static let attention = RGB(hex: 0xF19741)
    public static let error = RGB(hex: 0xE06C6C)
    public static let key = RGB(hex: 0x9DC3EE)
    public static let accent = RGB(hex: 0x00FF48)
}
