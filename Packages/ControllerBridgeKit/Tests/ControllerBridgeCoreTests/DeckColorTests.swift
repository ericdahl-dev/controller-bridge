import ControllerBridgeCore
import Testing

/// Deck colors follow Syndicate (#123): deck N is cue palette slot 2N−1 (user guide, CUE COLORS), live, for the ring
/// and the app's badges. Before a palette arrives, DeckColors.defaults.
@Suite("Deck colors")
struct DeckColorTests {
    static func onDeck(_ deck: Int) throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.setDeck(deck, controller: 0)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/\(deck)/Loaded", [.int(1)]))
        return rig
    }

    static func palette(_ rig: Rig, slot: Int32, _ red: Int32, _ green: Int32, _ blue: Int32) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(slot), .int(red), .int(green), .int(blue)]))
    }

    @Test("Palette slot 3 set to red (255, 0, 0) makes deck 2's ring red: 0b00_11_00_00 = 48")
    func slotThreeIsDeckTwo() throws {
        let rig = try Self.onDeck(2)
        Self.palette(rig, slot: 3, 255, 0, 0)
        #expect(rig.leds[40] == 48)
    }

    @Test("Slots 1, 5 and 7 are decks 1, 3 and 4: blue (0, 0, 255) lights 3", arguments: [(1, Int32(1)), (3, 5), (4, 7)])
    func oddSlotsAreDecks(deck: Int, slot: Int32) throws {
        let rig = try Self.onDeck(deck)
        Self.palette(rig, slot: slot, 0, 0, 255)
        #expect(rig.leds[40] == 3)
    }

    @Test("Even slots are cue colors only: slot 4 set to blue leaves deck 2's ring as it was")
    func evenSlotsLeaveDecksAlone() throws {
        let rig = try Self.onDeck(2)
        let before = rig.leds[40]
        Self.palette(rig, slot: 4, 0, 0, 255)
        #expect(rig.leds[40] == before)
    }

    @Test("A palette change repaints the ring at once: red, then green (0, 255, 0) = 12, with no other feedback")
    func paletteChangeRepaints() throws {
        let rig = try Self.onDeck(2)
        Self.palette(rig, slot: 3, 255, 0, 0)
        #expect(rig.leds[40] == 48)
        Self.palette(rig, slot: 3, 0, 255, 0)
        #expect(rig.leds[40] == 12)
    }

    @Test("Layers: with layer 2 in front (normal mode, LEDs on ch1), a palette change to slot 3 repaints its ring: 48")
    func paletteRepaintsActiveLayer() throws {
        let rig = try LayersTests.layered()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(1)]))
        LayersTests.note(rig, channel: 2, 51, 127)
        let output = try #require(rig.midi.outputs[Rig.lc6000Out.id])
        output.sent.removeAll()
        Self.palette(rig, slot: 3, 255, 0, 0)
        #expect(output.sent == [.noteOn(channel: 0, note: 40, velocity: 48)])
    }
}
