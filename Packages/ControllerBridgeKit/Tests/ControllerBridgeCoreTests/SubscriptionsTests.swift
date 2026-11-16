import ControllerBridgeCore
import Testing

/// Syndicate answers a Resend with every subscribed value, and always ColorPalette (user guide §14.10). An answer with
/// ColorPalette but no deck values means its OSC FEEDBACK subscriptions are off: LIVE, but every LED stays dark (#150).
@Suite("Feedback subscriptions")
struct SubscriptionsTests {
    static let palette = OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)])

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    @Test("The launch Resend answered with only ColorPalette, no deck or header values: no deck data, once its 2 s window closes")
    func onlyPalette() throws {
        let rig = try Rig()
        rig.coordinator.start()                  // sends a Resend at t = 0
        rig.clock.now = 0.3
        rig.coordinator.feedback(Self.palette)
        Self.tick(rig, at: 1.9)
        #expect(rig.coordinator.status.noDeckData == false)
        Self.tick(rig, at: 2.0)
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.coordinator.status.noDeckData == true)
    }

    /// No deck data flagged at t = 2.
    static func noDeckDataRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.3
        rig.coordinator.feedback(Self.palette)
        Self.tick(rig, at: 2.0)
        return rig
    }

    @Test("A deck or header value arriving later, any time, clears it: the subscriptions are on now", arguments: [
        "/Syndicate/Deck/2/Playing", "/Syndicate/Header/BPM",
    ])
    func deckValueClears(address: String) throws {
        let rig = try Self.noDeckDataRig()
        rig.clock.now = 30
        rig.coordinator.feedback(Self.palette)
        #expect(rig.coordinator.status.noDeckData == true)
        rig.coordinator.feedback(OSCMessage(address, [.int(1)]))
        #expect(rig.coordinator.status.noDeckData == false)
    }

    @Test("Empty decks with header values in the answer are plain LIVE: Syndicate sends nothing for an empty deck")
    func emptyDecksWithHeader() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.3
        rig.coordinator.feedback(Self.palette)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/BPM", [.float(120)]))
        Self.tick(rig, at: 2.0)
        #expect(rig.coordinator.status.noDeckData == false)
    }

    /// The launch Resend answered with `messages` at t = 0.3, and its window closed at t = 2.
    static func answered(_ messages: [OSCMessage]) throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.3
        for message in [Self.palette, OSCMessage("/Syndicate/Header/BPM", [.float(120)])] + messages {
            rig.coordinator.feedback(message)
        }
        Self.tick(rig, at: 2.0)
        return rig
    }

    @Test("A loaded deck without Cues in the answer: the Cues subscription is missing. Empty deck 2 counts for nothing")
    func loadedDeckWithoutCues() throws {
        let rig = try Self.answered(EverySubscriptionTests.deck1.filter { $0.0 != .cues }.map(\.1) + [
            OSCMessage("/Syndicate/Deck/2/Loaded", [.int(0)]),
        ])
        #expect(rig.coordinator.status.noDeckData == false)
        #expect(rig.coordinator.status.missingSubscriptions == [.cues])
    }

    /// Every subscription but Loaded and TrackInfo, which a deck with only Loaded proves (#211).
    static let allButLoaded: [Subscription] = [.playing, .playPending, .progress, .tempoSlider, .cues, .sync, .loop]

    @Test("A loaded deck with only Loaded: every other subscription is missing")
    func loadedDeckOnly() throws {
        let rig = try Self.answered([OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)])])
        #expect(rig.coordinator.status.missingSubscriptions == Self.allButLoaded)
    }

    @Test("A loaded deck with every value in the real capture: nothing is missing")
    func loadedDeckComplete() throws {
        let rig = try Self.answered(EverySubscriptionTests.deck1.map(\.1))
        #expect(rig.coordinator.status.missingSubscriptions == [])
    }

    @Test("Silence is never missing subscriptions: an unanswered Resend goes stale, with no deck data warning")
    func silenceFlagsNothing() throws {
        let rig = try Rig()
        rig.coordinator.start()
        Self.tick(rig, at: 2.0)
        #expect(rig.coordinator.status.noDeckData == false)
        #expect(rig.coordinator.status.missingSubscriptions == [])
    }

    @Test("A later complete answer clears an earlier gap: during a paused set, the quiet Resend gets every value again")
    func laterAnswerClearsGap() throws {
        let rig = try Self.answered([OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)])])
        #expect(rig.coordinator.status.missingSubscriptions == Self.allButLoaded)
        Self.tick(rig, at: 10.3)                 // 10 s quiet: the next Resend
        rig.clock.now = 10.5
        for message in EverySubscriptionTests.deck1.map(\.1) { rig.coordinator.feedback(message) }
        Self.tick(rig, at: 12.3)
        #expect(rig.coordinator.status.missingSubscriptions == [])
    }
}
