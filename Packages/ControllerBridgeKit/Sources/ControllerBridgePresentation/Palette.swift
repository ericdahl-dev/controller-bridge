/// One theme's colors, by what they're for (#127).
public struct ThemePalette: Equatable, Sendable {
    // Surfaces, darkest first in the dark theme.
    public var background: RGB
    public var panel: RGB
    public var button: RGB
    public var buttonRaised: RGB
    public var hairline: RGB
    /// A button's edge: reads at 3:1 on both the panel and the button fill (#67).
    public var buttonEdge: RGB
    /// The bar under a selected tab or deck: the second, non-color cue for "selected" (#67).
    public var selectedBar: RGB

    // Text.
    public var text: RGB
    public var caption: RGB

    // State. Each is always paired with a word, never shown by color alone.
    public var live: RGB
    public var attention: RGB
    public var error: RGB
    public var key: RGB
    /// Syndicate's Signal Green as a fill, and the text that sits on it.
    public var accent: RGB
    public var onAccent: RGB
}

/// The bridge's colors are Syndicate's own (#127), from the CSS tokens in its user guide
/// (untitledaudiosyndicate.com/user-guide), which say they come "from the app's LookAndFeel greys, paper #EDEDEA and
/// Signal Green (Syndicate Branding/spec/tokens.json)". Each token's name is in a comment. Where a token's use would
/// miss WCAG AA here, a passing token takes its place, or it is darkened the least that passes; that is noted too.
/// Syndicate has no attention, error or key colors, so those are the bridge's, picked to pass in each theme.
public enum Palette {
    /// Syndicate's default theme.
    public static let dark = ThemePalette(
        background: RGB(hex: 0x171717),   // --ground
        panel: RGB(hex: 0x1B1B1B),        // --window
        button: RGB(hex: 0x1E1E1E),       // --key
        buttonRaised: RGB(hex: 0x2A2A2A), // --hl
        hairline: RGB(hex: 0x2E2E2E),     // --rule
        buttonEdge: RGB(hex: 0x7E7E7E),   // --fg-dim
        selectedBar: RGB(hex: 0xEDEDEA),  // --fg
        text: RGB(hex: 0xEDEDEA),         // --fg
        caption: RGB(hex: 0xBDBDBD),      // --fg-btn: --fg-dim is 4.24:1 on the window
        live: RGB(hex: 0x00FF48),         // --signal-text
        attention: RGB(hex: 0xF19741),
        error: RGB(hex: 0xE06C6C),
        key: RGB(hex: 0x9DC3EE),
        accent: RGB(hex: 0x00FF48),       // --signal
        onAccent: RGB(hex: 0x111111)      // --on-signal
    )

    /// Syndicate's LIGHT MODE.
    public static let light = ThemePalette(
        background: RGB(hex: 0xE6E6E4),   // --ground
        panel: RGB(hex: 0xDCDCDA),        // --window
        button: RGB(hex: 0xD6D6D4),       // --key
        buttonRaised: RGB(hex: 0xCFCFCD), // --hl
        hairline: RGB(hex: 0xC7C7C5),     // --rule
        buttonEdge: RGB(hex: 0x6F6F6F),   // --fg-dim
        selectedBar: RGB(hex: 0x1B1B1B),  // --fg
        text: RGB(hex: 0x1B1B1B),         // --fg
        caption: RGB(hex: 0x4F4F4F),      // --fg-label: --fg-dim is 3.66:1 on the window
        live: RGB(hex: 0x007026),         // --signal-text #007A29, darkened 8%: it is 4.01:1 on the window
        attention: RGB(hex: 0x9A4A00),
        error: RGB(hex: 0xA33B3B),
        key: RGB(hex: 0x2F5F9A),
        accent: RGB(hex: 0x00FF48),       // --signal
        onAccent: RGB(hex: 0x111111)      // --on-signal
    )

    // The dark theme's colors by name, for code that doesn't follow the appearance yet.
    public static let background = dark.background
    public static let panel = dark.panel
    public static let button = dark.button
    public static let buttonRaised = dark.buttonRaised
    public static let hairline = dark.hairline
    public static let buttonEdge = dark.buttonEdge
    public static let selectedBar = dark.selectedBar
    public static let text = dark.text
    public static let caption = dark.caption
    public static let live = dark.live
    public static let attention = dark.attention
    public static let error = dark.error
    public static let key = dark.key
    public static let accent = dark.accent
}
