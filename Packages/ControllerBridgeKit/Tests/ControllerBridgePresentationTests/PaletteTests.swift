import ControllerBridgePresentation
import Testing

/// Every text color the theme puts on a surface must reach WCAG AA for normal text (4.5:1). A failing pair means
/// the token changes, not the test.
@Suite("Palette")
struct PaletteTests {
    static let pairs: [(String, RGB, RGB)] = [
        ("text on background", Palette.text, Palette.background),
        ("text on panel", Palette.text, Palette.panel),
        ("text on button", Palette.text, Palette.button),
        ("text on raised button", Palette.text, Palette.buttonRaised),
        ("caption on background", Palette.caption, Palette.background),
        ("caption on panel", Palette.caption, Palette.panel),
        ("caption on button", Palette.caption, Palette.button),
        ("live green on background", Palette.live, Palette.background),
        ("live green on panel", Palette.live, Palette.panel),
        ("attention orange on background", Palette.attention, Palette.background),
        ("attention orange on panel", Palette.attention, Palette.panel),
        ("error red on background", Palette.error, Palette.background),
        ("error red on panel", Palette.error, Palette.panel),
        ("key blue on panel", Palette.key, Palette.panel),
    ]

    @Test("Every text and surface pair the theme uses reaches 4.5:1", arguments: pairs.indices)
    func aaContrast(index: Int) {
        let (name, foreground, surface) = Self.pairs[index]
        let ratio = Contrast.ratio(foreground, surface)
        #expect(ratio >= 4.5, "\(name): \(ratio)")
    }

    /// Non-text contrast (WCAG 1.4.11): a UI edge or a selection mark that is the only cue needs 3:1 against what's
    /// around it (#67).
    static let nonTextPairs: [(String, RGB, RGB)] = [
        ("button edge on panel", Palette.buttonEdge, Palette.panel),
        ("button edge on button", Palette.buttonEdge, Palette.button),
        ("selected bar on button", Palette.selectedBar, Palette.button),
        ("selected bar on raised button", Palette.selectedBar, Palette.buttonRaised),
    ]

    @Test("Button edges and the selected-item bar reach 3:1 where they are the only cue", arguments: nonTextPairs.indices)
    func nonTextContrast(index: Int) {
        let (name, mark, surface) = Self.nonTextPairs[index]
        let ratio = Contrast.ratio(mark, surface)
        #expect(ratio >= 3, "\(name): \(ratio)")
    }
}
