import ControllerBridgeCore
import ControllerBridgePresentation
import Testing

/// One source of truth for the deck colors (#122): the app's badges and the LC6000's ring use the same RGB. The two
/// targets don't depend on each other, so this test pins them together.
@Suite("Deck color source")
struct DeckColorSourceTests {
    @Test("Each deck badge's fill is Core's default deck color", arguments: 1...4)
    func badgeMatchesCore(deck: Int) {
        let fill = DeckBadge(deck: deck).fill
        #expect([Int(fill.red), Int(fill.green), Int(fill.blue)] == DeckColors.defaults[deck])
    }
}
