import ControllerBridgeCore
import Testing

/// The one list of Syndicate OSC FEEDBACK subscriptions (#211): the setup guide shows it and the check judges it.
@Suite("Subscription list")
struct SubscriptionListTests {
    @Test("All eight, in the setup guide's order, by the names Syndicate's OSC FEEDBACK screen uses")
    func names() {
        #expect(Subscription.allCases.map(\.syndicateName) == [
            "Playing", "PlayPending", "Loaded and TrackInfo", "Position/Progress", "TempoSlider/TempoSliderEnabled", "Cues",
            "BPM/Sync", "Loop",
        ])
    }

    @Test("Each says what breaks without it, in plain words")
    func breaks() {
        #expect(Subscription.tempoSlider.breaks == "the pitch fader can jump")
        #expect(Subscription.cues.breaks == "hot cue pads stay dark")
        #expect(Subscription.playPending.breaks == "Play won't blink while a quantized start waits")
        #expect(Subscription.allCases.allSatisfy { !$0.breaks.isEmpty })
    }

    @Test("Each is proven by any one of the deck values it sends (a load sends TempoSlider without TempoSliderEnabled)")
    func values() {
        #expect(Subscription.tempoSlider.values == ["temposlider", "temposliderenabled"])
        #expect(Subscription.loaded.values == ["loaded", "trackinfo"])
        #expect(Subscription.sync.values == ["sync"])
    }
}
