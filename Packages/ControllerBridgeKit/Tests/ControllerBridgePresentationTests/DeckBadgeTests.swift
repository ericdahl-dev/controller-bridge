import ControllerBridgePresentation
import Testing

/// Badge fills are sampled from Syndicate's deck headers. The digit is white or near-black, whichever reads better;
/// the ratios in the comments are worked from the WCAG formula.
@Suite("Deck badge")
struct DeckBadgeTests {
    @Test("Deck 1 is gray with a white digit (4.9:1; near-black would be 3.8:1)")
    func deckOne() {
        #expect(DeckBadge(deck: 1) == DeckBadge(fill: RGB(hex: 0x6C7277), digit: RGB(hex: 0xFFFFFF)))
    }

    @Test("Decks 2, 3 and 4 are yellow, orange-red and steel blue, each with a near-black digit", arguments: [
        (2, 0xECCF65), // near-black 12.0:1, white 1.5:1
        (3, 0xC5754E), // near-black 5.3:1, white 3.5:1
        (4, 0x62929E), // near-black 5.4:1, white 3.4:1
    ] as [(Int, UInt32)])
    func colorDecks(deck: Int, fill: UInt32) {
        #expect(DeckBadge(deck: deck) == DeckBadge(fill: RGB(hex: fill), digit: RGB(hex: 0x141415)))
    }

    @Test("A deck outside 1–4 gets a neutral raised-gray badge with a white digit (10.1:1)", arguments: [0, 5, -1])
    func neutralBadge(deck: Int) {
        #expect(DeckBadge(deck: deck) == DeckBadge(fill: RGB(hex: 0x424242), digit: RGB(hex: 0xFFFFFF)))
    }

    // #123: deck colors come from Syndicate's palette or the user, so the digit must be legible on any fill.

    @Test("Any fill gets a digit at 4.5:1 or better: every color on a 0-255 grid in steps of 17")
    func digitLegibleOnAnyFill() {
        var worst = 21.0
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let fill = RGB(hex: UInt32(red << 16 | green << 8 | blue))
                    let badge = DeckBadge(fill: fill)
                    worst = min(worst, Contrast.ratio(badge.digit, fill))
                }
            }
        }
        #expect(worst >= 4.5)
    }

    @Test("Yellow and pure red get a dark digit (red: 4.0:1 with white, 5.3:1 dark); navy gets white", arguments: [
        (UInt32(0xFFFF00), false), (0x000080, true), (0xFF0000, false),
    ])
    func digitByContrast(hex: UInt32, white: Bool) {
        #expect((DeckBadge(fill: RGB(hex: hex)).digit == RGB(hex: 0xFFFFFF)) == white)
    }
}
