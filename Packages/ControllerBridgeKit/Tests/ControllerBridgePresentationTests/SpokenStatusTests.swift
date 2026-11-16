import ControllerBridgePresentation
import Testing

/// What VoiceOver hears (#67): natural case, no glyphs ("black circle", "middle dot"), the same facts as the lights.
@Suite("Spoken status")
struct SpokenStatusTests {
    @Test("A light is spoken in natural case: our fixed labels are capitalized, words lowercased, device names kept")
    func spokenLights() {
        #expect(StatusLight(label: "Feedback", word: "Port 9096 in use", tone: .error).spoken == "Feedback: port 9096 in use")
        #expect(StatusLight(label: "Controller", word: "Not connected", tone: .idle).spoken == "Controller: not connected")
        #expect(StatusLight(label: "Denon LC6000 PRIME", word: "Connected", tone: .live).spoken == "Denon LC6000 PRIME: connected")
        #expect(StatusLight(label: "DDJ-FLX4", word: "No profile", tone: .attention).spoken == "DDJ-FLX4: no profile")
    }

    // Since #66 the controller light is always CONTROLLER; the panel header says which device it is.
    @Test("The status line is spoken as sentences: every light, every deck, then master; no dots or bullets")
    func spokenLine() {
        let one = StatusPresentation(BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096),
                                                 deck: 1, master: true))
        #expect(one.spokenLine == "Controller: connected. Feedback: live. Deck 1. Tempo master.")

        let two = StatusPresentation(BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .waiting(port: 9096),
                                                 deck: 1, others: [.init(controller: .notConnected, deck: 2)]))
        #expect(two.spokenLine == "Controller: connected. Feedback: waiting. Decks 1 and 2.")
    }
}

/// The menu-bar icon's VoiceOver label (#67), kept word for word through #171's change of case.
@Suite("Menu-bar icon label")
struct MenuBarIconLabelTests {
    @Test("The icon reads each light's label and word, in caps, as it always has")
    func iconLabel() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .portInUse(port: 9096),
                                                    deck: 1, demo: true))
        #expect(status.iconAccessibilityLabel == "DEMO CONTROLLER, CONTROLLER CONNECTED, FEEDBACK PORT 9096 IN USE")
    }
}
