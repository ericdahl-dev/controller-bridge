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

    /// What the app passes from Core's one list (#211): the LC6000's eight, the jog display off (#165).
    static let required = Subscription.always.map(\.syndicateName)

    static func missing(_ subscriptions: Subscription...) -> [MissingSubscription] {
        subscriptions.map { MissingSubscription(name: $0.syndicateName, breaks: $0.breaks) }
    }

    @Test("No deck data: help names the profile's subscriptions to turn on, and links the guide")
    func noDeckDataHelp() {
        let state = BridgeState(controller: Self.connected, feedback: .noDeckData(port: 9096), deck: 1,
                                requiredSubscriptions: Self.required)
        #expect(HelpMessage(state) == HelpMessage(
            text: "Syndicate isn't sending deck info. In Syndicate › Settings › OSC FEEDBACK, turn on the subscriptions: Playing, PlayPending, Loaded and TrackInfo, Position/Progress, TempoSlider and TempoSliderEnabled, Cues, BPM and Sync and Loop.",
            showsGuide: true
        ))
    }

    @Test("TempoSlider missing (the user's own Syndicate, #211): the light stays LIVE; help is a one-row list (#261)")
    func tempoSliderMissing() {
        let state = BridgeState(controller: Self.connected, feedback: .live(port: 9096), deck: 1,
                                missingSubscriptions: Self.missing(.tempoSlider))
        #expect(StatusPresentation(state).lights.contains(StatusLight(label: "Feedback", word: "Live", tone: .live, kind: .feedback)))
        #expect(HelpMessage(state) == HelpMessage(
            text: "Turn this on in Syndicate › OSC Feedback, then Save and Close:",
            showsGuide: true,
            subscriptions: [SubscriptionRow(name: "TempoSlider and TempoSliderEnabled", consequence: "The pitch fader can jump")]
        ))
    }

    @Test("The user's case, TempoSlider and Cues missing: a row each, in the guide's order, under the header")
    func severalMissing() {
        let state = BridgeState(controller: Self.connected, feedback: .live(port: 9096), deck: 1,
                                missingSubscriptions: Self.missing(.tempoSlider, .cues))
        #expect(HelpMessage(state) == HelpMessage(
            text: "Turn these on in Syndicate › OSC Feedback, then Save and Close:",
            showsGuide: true,
            subscriptions: [
                SubscriptionRow(name: "TempoSlider and TempoSliderEnabled", consequence: "The pitch fader can jump"),
                SubscriptionRow(name: "Cues", consequence: "Hot cue pads stay dark"),
            ]
        ))
    }

    @Test("VoiceOver hears the list as a list: the header and count, then each row as name and what it breaks")
    func voiceOver() {
        let state = BridgeState(controller: Self.connected, feedback: .live(port: 9096), deck: 1,
                                missingSubscriptions: Self.missing(.tempoSlider, .cues))
        let help = HelpMessage(state)
        #expect(help?.subscriptionsLabel == "2 subscriptions off. Turn these on in Syndicate › OSC Feedback, then Save and Close.")
        #expect(help?.subscriptions.map(\.spoken) == ["TempoSlider and TempoSliderEnabled: the pitch fader can jump",
                                                       "Cues: hot cue pads stay dark"])
    }

    @Test("A controller that needs a hand comes first: its LEDs can't show anything until it's connected")
    func controllerFirst() {
        let state = BridgeState(controller: .notConnected, feedback: .noDeckData(port: 9096), deck: 1)
        #expect(HelpMessage(state)?.text == "No controller connected. Plug it in over USB; the bridge finds it.")
    }

}
