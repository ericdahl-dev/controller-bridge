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

    @Test("The status carries the deck colors in use, for the app's badges: the defaults, then slot 3's red as deck 2")
    func statusCarriesDeckColors() throws {
        let rig = try Self.onDeck(1)
        #expect(rig.coordinator.status.deckColors == .defaults)
        Self.palette(rig, slot: 3, 255, 0, 0)
        #expect(rig.coordinator.status.deckColors[2] == [255, 0, 0])
        #expect(rig.coordinator.status.deckColors[1] == DeckColors.defaults[1])
    }

    @Test("With following off, the custom color wins over Syndicate's: deck 2 custom blue (0, 0, 255) = 3, even after slot 3 red")
    func customColorWins() throws {
        let rig = try Self.onDeck(2)
        var custom = DeckColors.defaults
        custom.rgb[2] = [0, 0, 255]
        rig.coordinator.setDeckColors(followSyndicate: false, custom: custom)
        #expect(rig.leds[40] == 3)
        Self.palette(rig, slot: 3, 255, 0, 0)
        #expect(rig.leds[40] == 3)
        #expect(rig.coordinator.status.deckColors[2] == [0, 0, 255])

        rig.coordinator.setDeckColors(followSyndicate: true, custom: custom)
        #expect(rig.leds[40] == 48)
    }

    @Test("A black palette slot keeps that deck's default color, so the ring never goes dark, and says so once in the log")
    func blackPaletteSlotFallsBack() throws {
        let rig = try Self.onDeck(2)
        let before = rig.leds[40]
        Self.palette(rig, slot: 3, 0, 0, 0)
        Self.palette(rig, slot: 3, 0, 0, 0)
        #expect(rig.leds[40] == before)
        #expect(rig.coordinator.status.deckColors[2] == DeckColors.defaults[2])
        #expect(rig.log.lines.filter { $0.contains("black") }
            == ["Syndicate's deck 2 color is black, which the LC6000's ring can't show; using the default"])
    }

    @Test("The LC6000 preview: each channel's rgb222 level × 85, and a dim color lifted as the ring lifts it", arguments: [
        ([236, 207, 101], [255, 170, 85]),
        ([108, 114, 119], [85, 85, 85]),
        ([10, 0, 0], [85, 0, 0]),
        ([0, 0, 0], [0, 0, 0]),
    ])
    func ledPreview(rgb: [Int], shown: [Int]) {
        #expect(DeckColors.ledPreview(rgb) == shown)
    }

    @Test("ColorPalette as Syndicate really sends it, an OSC array on the wire, moves deck 1's ring: slot 1 red = 48")
    func paletteFromWireArray() throws {
        let rig = try Self.onDeck(1)
        let packet = OSCCodecTests.bytes("""
            2f53796e 64696361 74652f43 6f6c6f72 50616c65 74746500
            2c5b6969 69695d00
            00000001 000000ff 00000000 00000000
            """)
        for message in try OSCPacket(decoding: packet).messages { rig.coordinator.feedback(message) }
        #expect(rig.leds[40] == 48)
        #expect(rig.coordinator.status.deckColors[1] == [255, 0, 0])
    }

    @Test("All eight slots in one ColorPalette message (flattened arrays): slot 3 red still moves deck 2's ring, 48")
    func paletteAllSlotsInOneMessage() throws {
        let rig = try Self.onDeck(2)
        let slots: [[Int32]] = [[1, 0, 0, 255], [2, 0, 255, 0], [3, 255, 0, 0], [4, 0, 0, 255],
                                [5, 0, 255, 255], [6, 0, 0, 255], [7, 128, 0, 255], [8, 255, 0, 255]]
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", slots.flatMap { $0 }.map { .int($0) }))
        #expect(rig.leds[40] == 48)
        #expect(rig.coordinator.status.deckColors[4] == [128, 0, 255])
    }

    // #151: the ring is vivid. Take out the white (the smallest channel), scale the strongest to level 3, drop a channel
    // under 35 % of it, quantize. A near-grey (saturation under 20 %) keeps the exact mapping.
    static let vividCases: [([Int32], UInt8)] = [
        ([255, 0, 0], 48),                      // red, unchanged
        ([128, 0, 255], 35),                    // purple: 50 % ≥ 35 %, so (2, 0, 3)
        ([0, 200, 180], 15),                    // teal-ish: (0, 3, 3)
        ([255, 180, 180], 48),                  // pastel: the white comes out, (3, 0, 0)
        ([0x6C, 0x72, 0x77], 21),               // near-grey: exact, (1, 1, 1)
    ]

    @Test("Vivid ring colors from Syndicate's palette (slot 1, deck 1)", arguments: vividCases)
    func vividRing(rgb: [Int32], velocity: UInt8) throws {
        let rig = try Self.onDeck(1)
        Self.palette(rig, slot: 1, rgb[0], rgb[1], rgb[2])
        #expect(rig.leds[40] == velocity)
    }

    @Test("Switching ring colors to Exact repaints at once: deck 2's yellow goes from vivid 56 to exact 57, and back")
    func ringColorsSwitch() throws {
        let rig = try Self.onDeck(2)
        #expect(rig.leds[40] == 56)
        rig.coordinator.setRingColors(.exact)
        #expect(rig.leds[40] == 57)
        rig.coordinator.setRingColors(.vivid)
        #expect(rig.leds[40] == 56)
    }

    @Test("The LC6000 preview follows the ring mode: Syndicate's yellow is (255, 170, 85) exact, (255, 170, 0) vivid")
    func previewFollowsMode() {
        #expect(DeckColors.ledPreview([236, 207, 101], mode: .exact) == [255, 170, 85])
        #expect(DeckColors.ledPreview([236, 207, 101], mode: .vivid) == [255, 170, 0])
        #expect(DeckColors.ledPreview([255, 180, 180], mode: .vivid) == [255, 0, 0])
    }
}
