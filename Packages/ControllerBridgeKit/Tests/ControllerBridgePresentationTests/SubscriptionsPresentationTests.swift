import ControllerBridgeCore
import ControllerBridgePresentation
import Testing

/// Syndicate's OSC FEEDBACK subscriptions off (#150): feedback is live, but no deck info comes, so the LEDs stay dark.
@Suite("Subscriptions presentation")
struct SubscriptionsPresentationTests {
    static let connected = BridgeState.Controller.connected(profile: "Denon LC6000 PRIME")

    @Test("No deck data: an orange FEEDBACK ● NO DECK DATA light")
    func noDeckDataLight() {
        let status = StatusPresentation(BridgeState(controller: Self.connected, feedback: .noDeckData(port: 9096), deck: 1))
        #expect(status.lights.contains(StatusLight(label: "Feedback", word: "No deck data", tone: .attention, kind: .feedback)))
    }

    @Test("No deck data: help names the subscriptions to turn on, and links the guide")
    func noDeckDataHelp() {
        #expect(HelpMessage(BridgeState(controller: Self.connected, feedback: .noDeckData(port: 9096), deck: 1)) == HelpMessage(
            text: "Syndicate isn't sending deck info. In Syndicate › Settings › OSC FEEDBACK, turn on the subscriptions: Playing, PlayPending, Loaded and TrackInfo, Position/Progress, TempoSlider/TempoSliderEnabled, Cues, BPM/Sync and Loop.",
            showsGuide: true
        ))
    }

    @Test("Cues missing on a loaded deck: the light stays LIVE, and help says the pad colors need the Cues subscription")
    func cuesMissing() {
        let state = BridgeState(controller: Self.connected, feedback: .live(port: 9096), deck: 1, missingSubscriptions: ["cues"])
        #expect(StatusPresentation(state).lights.contains(StatusLight(label: "Feedback", word: "Live", tone: .live, kind: .feedback)))
        #expect(HelpMessage(state) == HelpMessage(
            text: "Hot cue pad colors need the Cues subscription. Turn it on in Syndicate › Settings › OSC FEEDBACK.",
            showsGuide: true
        ))
    }

    @Test("Several missing: one sentence names each LED and each subscription, in order")
    func severalMissing() {
        let state = BridgeState(controller: Self.connected, feedback: .live(port: 9096), deck: 1,
                                missingSubscriptions: ["playing", "sync", "loop"])
        #expect(HelpMessage(state) == HelpMessage(
            text: "The Play LED, the Sync LED and the loop LEDs need the Playing, BPM/Sync and Loop subscriptions. Turn them on in Syndicate › Settings › OSC FEEDBACK.",
            showsGuide: true
        ))
    }

    @Test("A controller that needs a hand comes first: its LEDs can't show anything until it's connected")
    func controllerFirst() {
        let state = BridgeState(controller: .notConnected, feedback: .noDeckData(port: 9096), deck: 1)
        #expect(HelpMessage(state)?.text == "No controller connected. Plug it in over USB; the bridge finds it.")
    }

    @Test("Every LED subscription the bridge checks is named as the setup guide and README name it", arguments: Subscription.allCases)
    func namesMatchGuide(subscription: Subscription) {
        let name = SetupGuide.subscriptionName(for: subscription.rawValue)
        #expect(name.map(SetupGuide.subscriptions.contains) == true, "\(subscription): \(String(describing: name))")
    }
}
