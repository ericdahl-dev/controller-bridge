import Foundation
@testable import ControllerBridgeCore
import Testing

/// The jog display controller (#384): the deck in front, the needles and the display, from plain values per controller
/// entry, not the Coordinator's or the Bridge's internals.
@Suite("Jog display controller: the deck in front")
struct JogDisplayFrontTests {
    typealias Entry = JogDisplayController.Entry

    static func entry(deck: Int, connected: Bool = true, ownsDisplay: Bool = false, activeLayer: Bool = false,
                      loaded: Bool = false) -> Entry {
        var facts = DeckFacts(deck: deck)
        facts.loaded = loaded
        return Entry(connected: connected, ownsDisplay: ownsDisplay, activeLayer: activeLayer, facts: facts)
    }

    @Test("Connected: the active layer, else the first connected entry")
    func activeLayerElseFirst() {
        #expect(JogDisplayController.front([Self.entry(deck: 1), Self.entry(deck: 2, activeLayer: true)], previewDeck: nil) == 1)
        #expect(JogDisplayController.front([Self.entry(deck: 1, connected: false), Self.entry(deck: 2)], previewDeck: nil) == 1)
        #expect(JogDisplayController.front([Self.entry(deck: 1), Self.entry(deck: 2)], previewDeck: nil) == 0)
    }

    @Test("An entry whose profile owns the display's port comes first (#305): its active layer, else its first")
    func ownerFirst() {
        let entries = [Self.entry(deck: 1, activeLayer: true), Self.entry(deck: 2, ownsDisplay: true),
                       Self.entry(deck: 3, ownsDisplay: true, activeLayer: true)]
        #expect(JogDisplayController.front(entries, previewDeck: nil) == 2)
        #expect(JogDisplayController.front(Array(entries.prefix(2)), previewDeck: nil) == 1)
    }

    @Test("None connected, the preview follows the picked deck, else the first loaded one, else the first (#221)")
    func preview() {
        let entries = [Self.entry(deck: 1, connected: false), Self.entry(deck: 2, connected: false, loaded: true),
                       Self.entry(deck: 3, connected: false)]
        #expect(JogDisplayController.front(entries, previewDeck: 3) == 2)
        #expect(JogDisplayController.front(entries, previewDeck: nil) == 1)
        #expect(JogDisplayController.front(entries, previewDeck: 4) == 1)   // no entry for deck 4: the first loaded
        #expect(JogDisplayController.front(Array(entries.prefix(1)), previewDeck: nil) == 0)
        #expect(JogDisplayController.front([], previewDeck: nil) == nil)
    }
}
