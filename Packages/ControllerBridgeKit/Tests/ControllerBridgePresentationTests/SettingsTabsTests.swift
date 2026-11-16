import ControllerBridgeCore
import ControllerBridgePresentation
import Testing

/// Settings in four tabs (#171): which tab each field lives on, and what a refused Apply does.
@Suite("Settings tabs")
struct SettingsTabsTests {
    @Test("Four tabs in order, each with its ⌘ number: Controller, Decks, Syndicate, General")
    func tabs() {
        #expect(SettingsTab.allCases.map(\.title) == ["Controller", "Decks", "Syndicate", "General"])
        #expect(SettingsTab.allCases.map(\.shortcut) == ["1", "2", "3", "4"])
    }

    @Test("Each field shows on its tab: devices, deck and channel on Controller; deck colors on Decks; host and ports on Syndicate")
    func fieldTabs() {
        #expect(SettingsTab(field: .deck(controller: 1)) == .controller)
        #expect(SettingsTab(field: .channel(controller: 0)) == .controller)
        #expect(SettingsTab(field: .device(controller: 2)) == .controller)
        #expect(SettingsTab(field: .deckColor(deck: 3)) == .decks)
        #expect(SettingsTab(field: .host) == .syndicate)
        #expect(SettingsTab(field: .oscPort) == .syndicate)
        #expect(SettingsTab(field: .feedbackPort) == .syndicate)
    }
}
