import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed at the Coordinator seam (#490, #616): Syndicate's feedback and the controller's MIDI in, the feed's
/// OSC out to its own fake port. Syndicate's factory deck colors (#123): deck 1 red, deck 2 yellow.
@Suite("Display feed at the Coordinator")
struct DisplayFeedCoordinatorTests {
    static let on = DisplayFeedSettings(enabled: true, host: "192.168.1.40", port: 9100)

    /// Turns the feed on as the app does: the setting, then its destination opening. `heard`: Syndicate's cue palette
    /// came first (its factory deck colors), so the first snapshot doesn't wait for it.
    static func turnOn(_ rig: Rig, _ settings: DisplayFeedSettings = on, heard: Bool = true) {
        if heard { rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)])) }
        rig.coordinator.setDisplayFeed(settings)
        rig.coordinator.displayFeedReady()
    }

    /// A rig with the feed's port attached, the feed still off.
    static func rig() throws -> (Rig, Rig.FakeOSC) {
        let rig = try Rig()
        let feed = Rig.FakeOSC()
        rig.coordinator.attachDisplayFeed(feed)
        return (rig, feed)
    }

    /// The full snapshot of a deck, in the feed's order: an empty deck when `title` is nil. The rest default to
    /// Daybreak's TrackInfo with no BPM feedback yet: A#m at 128, 0%.
    static func snapshot(deck: Int, color: Int32, title: String? = nil, artist: String = "", key: String = "A#m",
                         bpm: Float = 128, tempo: Float = 0) -> [OSCMessage] {
        let loaded = title != nil
        return [
            OSCMessage("/DeckBridge/Display/deck", [.int(Int32(deck))]),
            OSCMessage("/DeckBridge/Display/color", [.int(color)]),
            OSCMessage("/DeckBridge/Display/loaded", [.int(loaded ? 1 : 0)]),
            OSCMessage("/DeckBridge/Display/title", [.string(title ?? "")]),
            OSCMessage("/DeckBridge/Display/artist", [.string(loaded ? artist : "")]),
            OSCMessage("/DeckBridge/Display/key", [.string(loaded ? key : "")]),
            OSCMessage("/DeckBridge/Display/bpm", [.float(loaded ? bpm : 0)]),
            OSCMessage("/DeckBridge/Display/tempo", [.float(loaded ? tempo : 0)]),
            OSCMessage("/DeckBridge/Display/playing", [.int(0)]),
            OSCMessage("/DeckBridge/Display/cue", [.int(0)]),
            OSCMessage("/DeckBridge/Display/sync", [.int(0)]),
            OSCMessage("/DeckBridge/Display/master", [.int(0)]),
            OSCMessage("/DeckBridge/Display/loop", [.int(0)]),
            OSCMessage("/DeckBridge/Display/loopLength", [.float(0)]),
            OSCMessage("/DeckBridge/Display/beat", [.int(0)]),
            OSCMessage("/DeckBridge/Display/elapsed", [.int(0)]),
            OSCMessage("/DeckBridge/Display/remaining", [.int(loaded ? 428 : 0)]),
            OSCMessage("/DeckBridge/Display/progress", [.float(0)]),
            OSCMessage("/DeckBridge/Display/phase", [.float(-1)]),
        ]
    }

    static func message(_ name: String, _ value: Int32) -> OSCMessage { OSCMessage("/DeckBridge/Display/" + name, [.int(value)]) }
    static func message(_ name: String, _ value: Float) -> OSCMessage { OSCMessage("/DeckBridge/Display/" + name, [.float(value)]) }

    /// Syndicate loads a track on `deck`: Loaded, then its TrackInfo.
    static func load(_ rig: Rig, deck: Int = 1, title: String = "Daybreak") {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/\(deck)/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: deck, title: title))
    }

    @Test("Turned on with a controller connected: one snapshot of its deck's number, color, title and artist")
    func onSendsSnapshot() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        #expect(feed.sent == [])
        Self.turnOn(rig)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }

    @Test("Turned on, nothing goes out until the destination opens: the setting alone could reach the old address")
    func waitsForTheDestination() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        rig.coordinator.setDisplayFeed(Self.on)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        for step in 1...10 { rig.clock.now = Double(step) * 0.01; rig.coordinator.tick() }
        #expect(feed.sent == [])
        rig.coordinator.displayFeedReady()
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Nightfall", artist: "Bill Hamel, Jeremus"))
    }

    @Test("At launch, the first snapshot waits for Syndicate's answer: its deck colors and the deck in front, with its track, then goes once (#617's live check)")
    func holdsForSyndicatesAnswer() throws {
        let (rig, feed) = try Self.rig()
        Self.layered(rig)
        rig.midi.sources.removeAll { $0.id == Rig.lc6000.id }
        rig.coordinator.devicesChanged()
        Self.turnOn(rig, heard: false)
        #expect(feed.sent == [])
        // Syndicate answers the resend: its cue palette (deck 3 teal), then deck 3's load.
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(5), .int(0), .int(0xF5), .int(0xFF)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)]))
        #expect(feed.sent == [])
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 3, title: "Nightfall"))
        #expect(feed.sent == Self.snapshot(deck: 3, color: 0x00F5FF, title: "Nightfall", artist: "Bill Hamel, Jeremus"))
    }

    @Test("The deck known but Syndicate's palette not yet: still held, then one snapshot in the palette's color")
    func holdsForThePalette() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.turnOn(rig, heard: false)
        Self.load(rig)
        #expect(feed.sent == [])
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(0), .int(0xF5), .int(0xFF)]))
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0x00F5FF, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }

    @Test("With no answer from Syndicate, the first snapshot goes after a second anyway, with what's known")
    func holdIsBounded() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.turnOn(rig, heard: false)
        for step in 1...99 { rig.clock.now = Double(step) * 0.01; rig.coordinator.tick() }
        #expect(feed.sent == [])
        rig.clock.now = 1
        rig.coordinator.tick()
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000))
    }

    @Test("Turned on later, with Syndicate already heard, the snapshot goes at once; with DeckBridge's own colors, the palette isn't waited for")
    func noHoldOnceHeard() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.setDeckColors(followSyndicate: false, custom: DeckColors.defaults)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        Self.turnOn(rig, heard: false)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000))
    }

    @Test("Only changes go out: a new title sends the title alone; the same feedback again sends nothing")
    func changesOnly() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.turnOn(rig)
        Self.load(rig)
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
        Self.load(rig, deck: 1)
        Self.load(rig, deck: 2)
        Self.turnOn(rig)
        #expect(feed.sent.first == OSCMessage("/DeckBridge/Display/deck", [.int(1)]))
        feed.sent.removeAll()
        LayersTests.switchLayer(rig, from: 1, to: 2)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }

    @Test("A new host or port sends nothing to the old one; its destination opening sends the full snapshot; the same setting again sends nothing")
    func addressChangeSnapshot() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent == [])
        var moved = Self.on
        moved.host = "deck-panel.local"
        rig.coordinator.setDisplayFeed(moved)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        #expect(feed.sent == [])
        rig.coordinator.displayFeedReady()
        let nightfall = Self.snapshot(deck: 1, color: 0xFF0000, title: "Nightfall", artist: "Bill Hamel, Jeremus")
        #expect(feed.sent == nightfall)
        feed.sent.removeAll()
        moved.port = 9200
        Self.turnOn(rig, moved)
        #expect(feed.sent == nightfall)
    }

    @Test("Off: nothing goes out through loads and ticks; on again: the full snapshot, with what changed meanwhile")
    func offAndOnAgain() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        var off = Self.on
        off.enabled = false
        rig.coordinator.setDisplayFeed(off)
        feed.sent.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(title: "Nightfall"))
        for step in 1...10 { rig.clock.now = Double(step) * 0.01; rig.coordinator.tick() }
        #expect(feed.sent == [])
        Self.turnOn(rig)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Nightfall", artist: "Bill Hamel, Jeremus"))
    }

    @Test("No controller connected, jog display off and no WD port: the feed follows the deck the preview follows")
    func noControllerFollowsPreview() throws {
        let (rig, feed) = try Self.rig()
        Self.layered(rig)
        rig.midi.sources.removeAll { $0.id == Rig.lc6000.id }
        rig.coordinator.devicesChanged()
        Self.load(rig, deck: 3, title: "Nightfall")
        Self.turnOn(rig)
        // No pick: the first loaded deck.
        #expect(feed.sent.first == OSCMessage("/DeckBridge/Display/deck", [.int(3)]))
        feed.sent.removeAll()
        rig.coordinator.setJogPreviewDeck(2)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00))
    }

    @Test("A deck that's unloaded sends the empty state: loaded 0, \"\" for title and artist, never the last track")
    func emptyDeck() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        #expect(feed.sent == [
            OSCMessage("/DeckBridge/Display/loaded", [.int(0)]),
            OSCMessage("/DeckBridge/Display/title", [.string("")]),
            OSCMessage("/DeckBridge/Display/artist", [.string("")]),
            OSCMessage("/DeckBridge/Display/key", [.string("")]),
            OSCMessage("/DeckBridge/Display/bpm", [.float(0)]),
            OSCMessage("/DeckBridge/Display/remaining", [.int(0)]),
        ])
    }

    @Test("From the app's pipe: the setting, then the destination opening, send one full snapshot, not two (#617's live check); a later opening sends it again")
    func fromThePipe() async throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        let pipe = EventPipe()
        pipe.producer.send(.setDisplayFeed(Self.on))
        pipe.producer.send(.displayFeedReady)
        // The Mac woke and the destination opened again.
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
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.setDeck(2, controller: 0)
        #expect(feed.sent == Self.snapshot(deck: 2, color: 0xFFFF00))
    }

    @Test("TrackInfo with no Loaded yet is still the empty state; Loaded then sends loaded 1 with the track")
    func loadedIsTheFlag() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        Self.turnOn(rig)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000))
        feed.sent.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        #expect(feed.sent == [])
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        // loaded through bpm, and the time left: the rest (0% tempo, the flags, 0 s gone) were already the empty state's.
        #expect(feed.sent == Array(Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus")[2..<7])
            + [Self.message("remaining", Int32(428))])
    }

    @Test("The deck's live BPM sends bpm and tempo, the change from the track's BPM in percent: 132 on a 128 track is +3.125%")
    func bpmAndTempo() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/BPM", [.float(132)]))
        #expect(feed.sent == [
            OSCMessage("/DeckBridge/Display/bpm", [.float(132)]),
            OSCMessage("/DeckBridge/Display/tempo", [.float(3.125)]),
        ])
    }

    @Test("A track with no BPM of its own: tempo 0, bpm the live one")
    func tempoWithNoTrackBPM() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(bpm: 0))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/BPM", [.float(124)]))
        Self.turnOn(rig)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus", bpm: 124))
    }

    @Test("The key in Settings' notation, as the jog display writes it: Camelot sends A#m as 3A at once")
    func keyNotation() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.setKeyDisplay(.camelot)
        #expect(feed.sent == [OSCMessage("/DeckBridge/Display/key", [.string("3A")])])
    }

    @Test("Play, CUE held, sync and master each send their 0/1 as they change; master is synced with the tempo slider enabled")
    func transportFlags() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        MainCueTests.feed(rig, "Playing", 1)
        #expect(feed.sent == [Self.message("playing", Int32(1))])
        feed.sent.removeAll()
        TransportTests.press(rig, 2)
        #expect(feed.sent == [Self.message("cue", Int32(1))])
        feed.sent.removeAll()
        TransportTests.release(rig, 2)
        #expect(feed.sent == [Self.message("cue", Int32(0))])
        feed.sent.removeAll()
        MainCueTests.feed(rig, "Sync", 1)
        #expect(feed.sent == [Self.message("sync", Int32(1)), Self.message("master", Int32(1))])
        feed.sent.removeAll()
        MainCueTests.feed(rig, "TempoSliderEnabled", 0)
        #expect(feed.sent == [Self.message("master", Int32(0))])
    }

    @Test("A loop sends loop 1 and its length in beats at the track's BPM, fractions too: 1.875 s at 128 is 4, 0.234375 s is 0.5")
    func loopAndLength() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/LoopInfo", [.int(1), .float(10), .float(11.875)]))
        MainCueTests.feed(rig, "Loop", 1)
        #expect(feed.sent == [Self.message("loop", Int32(1)), Self.message("loopLength", Float(4))])
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/LoopInfo", [.int(1), .float(10), .float(10.234375)]))
        #expect(feed.sent == [Self.message("loopLength", Float(0.5))])
        feed.sent.removeAll()
        MainCueTests.feed(rig, "Loop", 0)
        #expect(feed.sent == [Self.message("loop", Int32(0)), Self.message("loopLength", Float(0))])
    }

    @Test("beat is Syndicate's master clock, 1-4, as the jog ring shows it; 0 once the clock has been quiet for over 2 s")
    func masterBeat() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(1)]))
        rig.clock.now = 0.5
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(2)]))
        #expect(feed.sent == [Self.message("beat", Int32(1)), Self.message("beat", Int32(2))])
        feed.sent.removeAll()
        rig.clock.now = 2.5
        rig.coordinator.tick()
        #expect(feed.sent == [])
        rig.clock.now = 2.51
        rig.coordinator.tick()
        #expect(feed.sent == [Self.message("beat", Int32(0))])
    }

    @Test("An empty deck sends beat 0 whatever the clock")
    func emptyDeckBeat() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        Self.turnOn(rig)
        feed.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(3)]))
        #expect(feed.sent == [])
    }

    @Test("elapsed and remaining in whole seconds, as the drawn display counts them: they change once a second, not with every Position")
    func trackTime() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        MainCueTests.position(rig, 30.7)
        #expect(feed.sent == [Self.message("elapsed", Int32(30)), Self.message("remaining", Int32(398))])
        feed.sent.removeAll()
        MainCueTests.position(rig, 30.9)
        #expect(feed.sent == [])
        MainCueTests.position(rig, 31.0)
        #expect(feed.sent == [Self.message("elapsed", Int32(31)), Self.message("remaining", Int32(397))])
    }

    @Test("progress, 0-1 through the track, goes out at most every 1/30 s; held, the latest value goes, never a queue of old ones")
    func progressRateLimit() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        // Daybreak is 428.5 s.
        rig.clock.now = 0.01
        MainCueTests.position(rig, 107.125)
        rig.clock.now = 0.02
        MainCueTests.position(rig, 214.25)
        rig.clock.now = 0.03
        rig.coordinator.tick()
        #expect(!feed.sent.contains { $0.address.hasSuffix("/progress") })
        rig.clock.now = 0.034
        rig.coordinator.tick()
        #expect(feed.sent.filter { $0.address.hasSuffix("/progress") } == [Self.message("progress", Float(0.5))])
        feed.sent.removeAll()
        rig.clock.now = 0.04
        MainCueTests.position(rig, 321.375)
        #expect(!feed.sent.contains { $0.address.hasSuffix("/progress") })
        rig.clock.now = 0.068
        rig.coordinator.tick()
        #expect(feed.sent.filter { $0.address.hasSuffix("/progress") } == [Self.message("progress", Float(0.75))])
    }

    @Test("A second of Position at 100 a second sends progress about 30 times, the last one where the deck is")
    func progressAbout30PerSecond() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        Self.turnOn(rig)
        feed.sent.removeAll()
        for step in 1...100 {
            rig.clock.now = Double(step) * 0.01
            MainCueTests.position(rig, Float(step))
            rig.coordinator.tick()
        }
        let progress = feed.sent.filter { $0.address.hasSuffix("/progress") }
        #expect((28...31).contains(progress.count))
        rig.clock.now = 1.1
        rig.coordinator.tick()
        #expect(feed.sent.last { $0.address.hasSuffix("/progress") } == Self.message("progress", Float(100.0 / 428.5)))
    }

    @Test("phase against the master, 0-1 with 0.5 in phase, by the drawn display's rule; -1 while unknown: stopped, or no offset yet")
    func phase() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        Self.load(rig)
        MainCueTests.feed(rig, "Playing", 1)
        Self.turnOn(rig)
        #expect(feed.sent.last == Self.message("phase", Float(-1)))
        feed.sent.removeAll()
        func offset(_ beats: Float, at time: Double) {
            rig.clock.now = time
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/PhaseOffset", [.float(beats)]))
        }
        func phases() -> [OSCMessage] { feed.sent.filter { $0.address.hasSuffix("/phase") } }
        // A quarter beat ahead, then (inside the same 1/30 s) a quarter behind: only the latest goes, at the slot.
        offset(0.25, at: 0.05)
        #expect(phases() == [Self.message("phase", Float(0.75))])
        offset(-0.25, at: 0.06)
        #expect(phases() == [Self.message("phase", Float(0.75))])
        rig.clock.now = 0.09
        rig.coordinator.tick()
        #expect(phases() == [Self.message("phase", Float(0.75)), Self.message("phase", Float(0.25))])
        feed.sent.removeAll()
        // Under the rule's 0.002 beats: in phase.
        offset(0.001, at: 0.2)
        #expect(phases() == [Self.message("phase", Float(0.5))])
        feed.sent.removeAll()
        rig.clock.now = 0.3
        MainCueTests.feed(rig, "Playing", 0)
        #expect(phases() == [Self.message("phase", Float(-1))])
    }

    @Test("Syndicate changing the deck's color sends the color alone")
    func colorChange() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(0)]))
        Self.turnOn(rig)
        feed.sent.removeAll()
        // Cue palette slot 1, deck 1's color (#123), now blue.
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(0), .int(0), .int(255)]))
        #expect(feed.sent == [OSCMessage("/DeckBridge/Display/color", [.int(0x0000FF)])])
    }
}
