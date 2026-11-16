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

    @Test("A refused Apply goes to the leftmost tab with a problem, and focuses that tab's first bad field")
    func refusalGoesToFirstTab() {
        let refusal = SettingsRefusal(fields: [
            SettingsProblem(field: .feedbackPort, message: "Feedback port 0 is out of range, expected 1-65535"),
            SettingsProblem(field: .deckColor(deck: 2), message: "Deck 2's color needs three values"),
            SettingsProblem(field: .host, message: "The Syndicate host can't be empty"),
        ])
        #expect(refusal.tab == .decks)
        #expect(refusal.focus == .deckColor(deck: 2))

        let syndicate = SettingsRefusal(fields: [
            SettingsProblem(field: .feedbackPort, message: "Feedback port 0 is out of range, expected 1-65535"),
            SettingsProblem(field: .host, message: "The Syndicate host can't be empty"),
        ])
        #expect(syndicate.tab == .syndicate)
        #expect(syndicate.focus == .feedbackPort)
    }

    @Test("A refusal with no field, such as the bridge not running, stays on the tab you're on")
    func refusalWithoutField() {
        let refusal = SettingsRefusal(fields: [], other: ["The bridge isn't running"])
        #expect(refusal.tab == nil)
        #expect(refusal.focus == nil)
    }

    @Test("The footer names each problem's tab, in tab order, then the problems with no field; VoiceOver hears them all")
    func footerAndAnnouncement() {
        let refusal = SettingsRefusal(
            fields: [
                SettingsProblem(field: .host, message: "The Syndicate host can't be empty"),
                SettingsProblem(field: .channel(controller: 0), message: "Channel 17 is out of range, expected 1-16"),
            ],
            other: ["The bridge isn't running"]
        )
        #expect(refusal.footer == [
            "Controller: Channel 17 is out of range, expected 1-16",
            "Syndicate: The Syndicate host can't be empty",
            "The bridge isn't running",
        ])
        #expect(refusal.announcement == "Settings not applied. Controller: Channel 17 is out of range, expected 1-16. "
            + "Syndicate: The Syndicate host can't be empty. The bridge isn't running.")
    }
}
