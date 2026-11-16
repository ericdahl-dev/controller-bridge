import ControllerBridgePresentation
import Testing

/// Every text color the theme puts on a surface must reach WCAG AA for normal text (4.5:1). A failing pair means
/// the token changes, not the test.
@Suite("Palette")
struct PaletteTests {
    static func pairs(_ p: ThemePalette) -> [(String, RGB, RGB)] {
        [
            ("text on background", p.text, p.background),
            ("text on panel", p.text, p.panel),
            ("text on button", p.text, p.button),
            ("text on raised button", p.text, p.buttonRaised),
            ("caption on background", p.caption, p.background),
            ("caption on panel", p.caption, p.panel),
            ("caption on button", p.caption, p.button),
            ("live green on background", p.live, p.background),
            ("live green on panel", p.live, p.panel),
            ("attention orange on background", p.attention, p.background),
            ("attention orange on panel", p.attention, p.panel),
            ("error red on background", p.error, p.background),
            ("error red on panel", p.error, p.panel),
            ("key blue on panel", p.key, p.panel),
            // #171: grouped cards on the surface, tonal pills on the raised button, dark ink on the green pill
            ("text on surface", p.text, p.surface),
            ("caption on surface", p.caption, p.surface),
            ("caption on raised button", p.caption, p.buttonRaised),
            ("live green on surface", p.live, p.surface),
            ("attention orange on surface", p.attention, p.surface),
            ("error red on surface", p.error, p.surface),
            ("ink on the accent pill", p.onAccent, p.accent),
        ]
    }

    static let themes: [(String, ThemePalette)] = [("dark", Palette.dark), ("light", Palette.light)]

    /// A chip (UNMAPPED, #171): its word on its tone's tint, composited over the window and over a card.
    @Test("A chip's word reaches 4.5:1 on its own tint, for every tone, on the window and on a card, in both themes",
          arguments: themes.indices)
    func chipContrast(theme: Int) {
        let (themeName, palette) = Self.themes[theme]
        for tone in [StatusLight.Tone.live, .idle, .attention, .error] {
            for (surfaceName, surface) in [("window", palette.panel), ("card", palette.surface)] {
                let tint = tone.color(in: palette).over(surface, opacity: Palette.chipTint)
                let ratio = Contrast.ratio(Palette.chipWord(in: palette), tint)
                #expect(ratio >= 4.5, "\(themeName) \(tone) chip on the \(surfaceName): \(ratio)")
            }
        }
    }

    @Test("Compositing: a color at an opacity over another, rounded per channel")
    func over() {
        #expect(RGB(hex: 0xFFFFFF).over(RGB(hex: 0x000000), opacity: 0.5) == RGB(hex: 0x808080))
        #expect(RGB(hex: 0x00FF48).over(RGB(hex: 0x1B1B1B), opacity: 0) == RGB(hex: 0x1B1B1B))
    }

    @Test("Every text and surface pair the theme uses reaches 4.5:1, in both themes (#127)", arguments: themes.indices)
    func aaContrast(theme: Int) {
        let (themeName, palette) = Self.themes[theme]
        for (name, foreground, surface) in Self.pairs(palette) {
            let ratio = Contrast.ratio(foreground, surface)
            #expect(ratio >= 4.5, "\(themeName) \(name): \(ratio)")
        }
    }

    /// Non-text contrast (WCAG 1.4.11): a UI edge or a selection mark that is the only cue needs 3:1 against what's
    /// around it (#67).
    static func nonTextPairs(_ p: ThemePalette) -> [(String, RGB, RGB)] {
        [
            ("button edge on panel", p.buttonEdge, p.panel),
            ("button edge on button", p.buttonEdge, p.button),
            ("selected bar on button", p.selectedBar, p.button),
            ("selected bar on raised button", p.selectedBar, p.buttonRaised),
            ("text-field edge on surface", p.buttonEdge, p.surface),
        ]
    }

    @Test("Button edges and the selected-item bar reach 3:1 where they are the only cue, in both themes", arguments: themes.indices)
    func nonTextContrast(theme: Int) {
        let (themeName, palette) = Self.themes[theme]
        for (name, mark, surface) in Self.nonTextPairs(palette) {
            let ratio = Contrast.ratio(mark, surface)
            #expect(ratio >= 3, "\(themeName) \(name): \(ratio)")
        }
    }

    /// The values are Syndicate's own (#127): its user guide's CSS tokens (untitledaudiosyndicate.com/user-guide,
    /// from the app's LookAndFeel grays, paper #EDEDEA and Signal Green, per Syndicate Branding/spec/tokens.json).
    @Test("Dark is Syndicate's default theme: ground, window, key, highlight, rule, fg, fg-btn, fg-dim, signal")
    func darkTokens() {
        let p = Palette.dark
        #expect(p.background == RGB(hex: 0x171717))   // --ground
        #expect(p.panel == RGB(hex: 0x1B1B1B))        // --window
        #expect(p.button == RGB(hex: 0x1E1E1E))       // --key
        #expect(p.buttonRaised == RGB(hex: 0x2A2A2A)) // --hl
        #expect(p.hairline == RGB(hex: 0x2E2E2E))     // --rule
        #expect(p.text == RGB(hex: 0xEDEDEA))         // --fg (paper)
        #expect(p.caption == RGB(hex: 0xBDBDBD))      // --fg-btn: --fg-dim is 4.24:1 on the window, short of AA
        #expect(p.buttonEdge == RGB(hex: 0x7E7E7E))   // --fg-dim, a 3:1 edge
        #expect(p.selectedBar == RGB(hex: 0xEDEDEA))  // --fg
        #expect(p.live == RGB(hex: 0x00FF48))         // --signal-text
        #expect(p.accent == RGB(hex: 0x00FF48))       // --signal
        #expect(p.onAccent == RGB(hex: 0x111111))     // --on-signal
        #expect(p.surface == RGB(hex: 0x20201F))      // the site's --p-surface (#171): cards on the window
    }

    @Test("Light is Syndicate's LIGHT MODE; live text is its --signal-text darkened 8%, the least that reaches AA on the window")
    func lightTokens() {
        let p = Palette.light
        #expect(p.background == RGB(hex: 0xE6E6E4))   // --ground
        #expect(p.panel == RGB(hex: 0xDCDCDA))        // --window
        #expect(p.button == RGB(hex: 0xD6D6D4))       // --key
        #expect(p.buttonRaised == RGB(hex: 0xCFCFCD)) // --hl
        #expect(p.hairline == RGB(hex: 0xC7C7C5))     // --rule
        #expect(p.text == RGB(hex: 0x1B1B1B))         // --fg
        #expect(p.caption == RGB(hex: 0x4F4F4F))      // --fg-label: --fg-dim is 3.66:1 on the window
        #expect(p.buttonEdge == RGB(hex: 0x6F6F6F))   // --fg-dim, a 3:1 edge
        #expect(p.selectedBar == RGB(hex: 0x1B1B1B))  // --fg
        #expect(p.live == RGB(hex: 0x007026))         // --signal-text #007a29 is 4.01:1 on the window
        #expect(p.accent == RGB(hex: 0x00FF48))       // --signal
        #expect(p.onAccent == RGB(hex: 0x111111))     // --on-signal
        #expect(p.surface == RGB(hex: 0xE6E6E4))      // lighter than the window, as the site's cards (#171)
    }
}
