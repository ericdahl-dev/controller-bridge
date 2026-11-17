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

/// Each deck's needle (#165, the user's pick): its own phase in the bar from DeckFacts' BarRamp at its BPM (else the
/// master's, else 120), a quarter turn a beat, never more than a quarter past the ramp; a pause holds it.
@Suite("Jog display controller: needles")
struct JogDisplayNeedleTests {
    static func playing(_ deck: Int = 1, bpm: Double?, ramp: Double, at: Double, playing: Bool = true) -> JogDisplayController.Entry {
        var facts = DeckFacts(deck: deck)
        facts.playing = playing
        facts.loaded = true
        facts.bpm = bpm
        facts.barRamp = DeckFacts.BarRamp(phase: ramp, at: at)
        return JogDisplayController.Entry(connected: true, ownsDisplay: true, activeLayer: true, facts: facts)
    }

    @Test("BarRamp 0 at 120 BPM: 0 at once, 2048 a quarter-second on (an eighth of a turn)")
    func runsAtTheDeckBPM() {
        let clock = Rig.FakeClock()
        let controller = JogDisplayController(clock: clock)
        controller.observe([Self.playing(bpm: 120, ramp: 0, at: 0)])
        #expect(controller.needle(0, at: 0) == 0)
        #expect(controller.needle(0, at: 0.25) == 2048)
    }

    @Test("No deck BPM: the master's (Header/BPM), else 120")
    func masterBPMElse120() {
        let controller = JogDisplayController(clock: Rig.FakeClock())
        controller.feedback(OSCMessage("/Syndicate/Header/BPM", [.float(60)]))
        controller.observe([Self.playing(bpm: nil, ramp: 0, at: 0)])
        #expect(controller.needle(0, at: 0.25) == 1024)   // 60 BPM: a sixteenth of a turn in a quarter-second
        let fresh = JogDisplayController(clock: Rig.FakeClock())
        fresh.observe([Self.playing(bpm: nil, ramp: 0, at: 0)])
        #expect(fresh.needle(0, at: 0.25) == 2048)
    }

    @Test("Paused, it holds where it was: BarRamp 0, paused a quarter-second on, still 2048 seconds later")
    func pauseHolds() {
        let clock = Rig.FakeClock()
        let controller = JogDisplayController(clock: clock)
        controller.observe([Self.playing(bpm: 120, ramp: 0, at: 0)])
        clock.now = 0.25
        controller.observe([Self.playing(bpm: 120, ramp: 0, at: 0, playing: false)])
        #expect(controller.needle(0, at: 5) == 2048)
    }

    @Test("A paused deck's BarRamp sets the needle without running on (a seek, #388)")
    func pausedRampSets() {
        let controller = JogDisplayController(clock: Rig.FakeClock())
        controller.observe([Self.playing(bpm: 120, ramp: 0.5, at: 1, playing: false)])
        #expect(controller.needle(0, at: 9) == 8192)
    }
}
