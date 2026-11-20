import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed at the Coordinator seam (#490, #616): Syndicate's feedback and the controller's MIDI in, the feed's
/// OSC out to its own fake port. Syndicate's factory deck colors (#123): deck 1 red, deck 2 yellow.
@Suite("Display feed at the Coordinator")
struct DisplayFeedCoordinatorTests {
    static let on = DisplayFeedSettings(enabled: true, host: "192.168.1.40", port: 9100)

    /// A rig with the feed's port attached, the feed still off.
    static func rig() throws -> (Rig, Rig.FakeOSC) {
        let rig = try Rig()
        let feed = Rig.FakeOSC()
        rig.coordinator.attachDisplayFeed(feed)
        return (rig, feed)
    }

    /// The full snapshot of a deck, in the feed's order.
    static func snapshot(deck: Int, color: Int32, title: String, artist: String) -> [OSCMessage] {
        [
            OSCMessage("/DeckBridge/Display/deck", [.int(Int32(deck))]),
            OSCMessage("/DeckBridge/Display/color", [.int(color)]),
            OSCMessage("/DeckBridge/Display/title", [.string(title)]),
            OSCMessage("/DeckBridge/Display/artist", [.string(artist)]),
        ]
    }

    @Test("Turned on with a controller connected: one snapshot of its deck's number, color, title and artist")
    func onSendsSnapshot() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        #expect(feed.sent == [])
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }

    @Test("Only changes go out: a new title sends the title alone; the same feedback again sends nothing")
    func changesOnly() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.setDisplayFeed(Self.on)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        feed.sent.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        #expect(feed.sent == [OSCMessage("/DeckBridge/Display/title", [.string("Nightfall")])])
        feed.sent.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        for step in 1...10 { rig.clock.now = Double(step) * 0.01; rig.coordinator.tick() }
        #expect(feed.sent == [])
    }

    /// The LC6000 as one entry per layer, as the app runs it, on layer 1.
    static func layered(_ rig: Rig) {
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers
        ))
    }

    @Test("Switching layers to deck 2 sends its full snapshot in yellow, even the fields deck 1 shared")
    func deckChangeSnapshot() throws {
        let (rig, feed) = try Self.rig()
        Self.layered(rig)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 2))
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent.first == OSCMessage("/DeckBridge/Display/deck", [.int(1)]))
        feed.sent.removeAll()
        LayersTests.switchLayer(rig, from: 1, to: 2)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }

    @Test("A new host or port sends the full snapshot at once; the same setting again sends nothing")
    func addressChangeSnapshot() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        rig.coordinator.setDisplayFeed(Self.on)
        let daybreak = Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus")
        feed.sent.removeAll()
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent == [])
        var moved = Self.on
        moved.host = "deck-panel.local"
        rig.coordinator.setDisplayFeed(moved)
        #expect(feed.sent == daybreak)
        feed.sent.removeAll()
        moved.port = 9200
        rig.coordinator.setDisplayFeed(moved)
        #expect(feed.sent == daybreak)
    }

    @Test("Off: nothing goes out through loads and ticks; on again: the full snapshot, with what changed meanwhile")
    func offAndOnAgain() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        rig.coordinator.setDisplayFeed(Self.on)
        var off = Self.on
        off.enabled = false
        rig.coordinator.setDisplayFeed(off)
        feed.sent.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        for step in 1...10 { rig.clock.now = Double(step) * 0.01; rig.coordinator.tick() }
        #expect(feed.sent == [])
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Nightfall", artist: "Bill Hamel, Jeremus"))
    }

    @Test("No controller connected, jog display off and no WD port: the feed follows the deck the preview follows")
    func noControllerFollowsPreview() throws {
        let (rig, feed) = try Self.rig()
        Self.layered(rig)
        rig.midi.sources.removeAll { $0.id == Rig.lc6000.id }
        rig.coordinator.devicesChanged()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 3, title: "Nightfall"))
        rig.coordinator.setDisplayFeed(Self.on)
        // No pick: the first loaded deck.
        #expect(feed.sent.first == OSCMessage("/DeckBridge/Display/deck", [.int(3)]))
        feed.sent.removeAll()
        rig.coordinator.setJogPreviewDeck(2)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00, title: "", artist: ""))
    }

    @Test("A deck that's unloaded sends the empty state: \"\" for title and artist, never the last track")
    func emptyDeck() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        rig.coordinator.setDisplayFeed(Self.on)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        #expect(feed.sent == [
            OSCMessage("/DeckBridge/Display/title", [.string("")]),
            OSCMessage("/DeckBridge/Display/artist", [.string("")]),
        ])
    }

    @Test("From the app's pipe: the setting turns it on; the display's destination opening sends the full snapshot again")
    func fromThePipe() async throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        let pipe = EventPipe()
        pipe.producer.send(.setDisplayFeed(Self.on))
        pipe.producer.send(.displayFeedReady)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)
        let daybreak = Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus")
        #expect(feed.sent == daybreak + daybreak)
    }

    @Test("Settings' deck for a controller with no layers: the new deck's full snapshot goes out")
    func deckSetting() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.setDisplayFeed(Self.on)
        feed.sent.removeAll()
        rig.coordinator.setDeck(2, controller: 0)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00, title: "", artist: ""))
    }

    @Test("Syndicate changing the deck's color sends the color alone")
    func colorChange() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.setDisplayFeed(Self.on)
        feed.sent.removeAll()
        // Cue palette slot 1, deck 1's color (#123), now blue.
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(0), .int(0), .int(255)]))
        #expect(feed.sent == [OSCMessage("/DeckBridge/Display/color", [.int(0x0000FF)])])
    }
}
