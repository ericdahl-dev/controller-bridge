@testable import ControllerBridgeRender
import Testing

/// A long title wraps at words across two lines, as drawn on the round screen (#165 follow-up): line 1 is whole words
/// that fit, never cut; only line 2 ends in an ellipsis when the rest doesn't fit.
@Suite("Two-line title")
struct TitleWrapTests {
    @Test("Ten (Original Club Mix): whole words on line 1, the rest on line 2, no ellipsis in the middle")
    func ten() {
        #expect(JogDisplayRenderer.titleLines("Ten (Original Club Mix)") == ["Ten (Original", "Club Mix)"])
    }

    @Test("A title too long for two lines ends in an ellipsis on line 2 only, after whole words on line 1",
          arguments: ["Ten (Original Club Mix) Extended Edit", "Mark Knight Underworld Sander Van Doorn Remix Edition",
                      "Supercalifragilisticexpialidocious Remix"])
    func long(_ title: String) {
        let lines = JogDisplayRenderer.titleLines(title)
        #expect(lines.count == 2)
        #expect(!lines[0].contains("…"))
        #expect(lines[1].hasSuffix("…"))
        // What shows is the title's start, in order (a word too long for line 1 is broken across the lines).
        let shown = (lines[0] + lines[1].dropLast()).filter { $0 != " " }
        #expect(title.filter { $0 != " " }.hasPrefix(shown))
    }

    @Test("A title that fits at 26 px is one line, untouched; a short one that doesn't (Night Drive) wraps at 20 px instead of being cut")
    func short() {
        #expect(JogDisplayRenderer.titleLines("Daybreak") == ["Daybreak"])
        #expect(JogDisplayRenderer.titleSize("Daybreak") == 26)
        #expect(!JogDisplayRenderer.titleLines("Night Drive").joined().contains("…"))
        #expect(JogDisplayRenderer.titleSize("Night Drive") == 20)
        #expect(JogDisplayRenderer.titleSize("Ten (Original Club Mix)") == 20)
    }
}

/// Player types (#209): the badge for the known ones, the raw value cut to 4 letters for any other (Syndicate's
/// Automation decks show AUTO), and a title-less deck says what it is, never "OSC clip" for something else.
@Suite("Player type badge")
struct PlayerTypeBadgeTests {
    @Test("Known types, an Automation deck, an unknown one, and none")
    func badges() {
        #expect(JogDisplayRenderer.badge("track") == "TRK")
        #expect(JogDisplayRenderer.badge("osc") == "OSC")
        #expect(JogDisplayRenderer.badge("automation") == "AUTO")
        #expect(JogDisplayRenderer.badge("granular") == "GRAN")
        #expect(JogDisplayRenderer.badge("empty") == nil)
        #expect(JogDisplayRenderer.badge(nil) == nil)
    }

    @Test("Without a title: an OSC clip says so, another type says its own name, an empty deck says No track")
    func noTitle() {
        #expect(JogDisplayRenderer.untitled("osc") == ("OSC clip", "no title"))
        #expect(JogDisplayRenderer.untitled("automation") == ("Automation", "no title"))
        #expect(JogDisplayRenderer.untitled("empty") == ("No track", "Load a track"))
        #expect(JogDisplayRenderer.untitled(nil) == ("No track", "Load a track"))
    }
}
