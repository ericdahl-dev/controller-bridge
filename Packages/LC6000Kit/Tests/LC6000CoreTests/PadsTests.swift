import LC6000Core
import Testing

/// Pads, pad modes and cue colors (#18). Expected OSC is from the Python bridge (lc6000_bridge/bridge.py). Pads are
/// notes 32-39 and the mode buttons 27-30 in the default mapping. Pad and ring velocities are worked out by hand
/// from the PROVISIONAL 64-color table: 2 bits per channel, 0b00RRGGBB, each channel round(c / 255 * 3).
@Suite("Pads")
struct PadsTests {
    static let pad1: UInt8 = 32
    static let modeHotCue: UInt8 = 27
    static let modeRoll: UInt8 = 28
    static let modeSlicer: UInt8 = 29
    static let modeLoop: UInt8 = 30

    /// A started rig with the start-up Resend cleared, so only what the test does is left.
    static func startedRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func down(_ rig: Rig, _ note: UInt8) {
        rig.coordinator.midi(.noteOn(channel: 0, note: note, velocity: 127), source: Rig.lc6000.id)
    }

    static func up(_ rig: Rig, _ note: UInt8) {
        rig.coordinator.midi(.noteOff(channel: 0, note: note, velocity: 0), source: Rig.lc6000.id)
    }

    static func press(_ rig: Rig, _ note: UInt8) {
        down(rig, note)
        up(rig, note)
    }

    @Test("In Hot Cue mode (the default) a pad holds its hot cue: HotCue n 1, then HotCue n 0 on release")
    func hotCuePads() throws {
        let rig = try Self.startedRig()
        Self.press(rig, 32)
        Self.press(rig, 39)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(1)]),
            OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)]),
            OSCMessage("/Syndicate/Deck/1/HotCue", [.int(8), .int(1)]),
            OSCMessage("/Syndicate/Deck/1/HotCue", [.int(8), .int(0)]),
        ])
    }

    @Test("In Roll mode a pad holds a slip roll: pad 1 is ThirtySecond, pad 8 is Four")
    func rollPads() throws {
        let rig = try Self.startedRig()
        Self.press(rig, Self.modeRoll)
        Self.press(rig, 32)
        Self.press(rig, 39)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(0)]),
            OSCMessage("/Syndicate/Deck/1/SlipLoop/Four", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/SlipLoop/Four", [.int(0)]),
        ])
    }

    @Test("Roll sizes run ThirtySecond, Sixteenth, Eighth, Quarter, Half, One, Two, Four across the pads")
    func rollSizes() throws {
        let rig = try Self.startedRig()
        Self.press(rig, Self.modeRoll)
        for pad in UInt8(32)...39 { Self.down(rig, pad) }
        #expect(rig.osc.sent.map(\.address) == [
            "ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four",
        ].map { "/Syndicate/Deck/1/SlipLoop/" + $0 })
    }

    @Test("In Loop mode a pad sets a cue loop on press, and its release sends nothing")
    func loopPads() throws {
        let rig = try Self.startedRig()
        Self.press(rig, Self.modeLoop)
        Self.press(rig, 34)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/SetCueLoop", [.int(3)])])
    }

    @Test("In Slicer mode the pads send nothing (Syndicate has no slicer routes)")
    func slicerPads() throws {
        let rig = try Self.startedRig()
        Self.press(rig, Self.modeSlicer)
        Self.press(rig, 32)
        #expect(rig.osc.sent == [])
    }

    @Test("Switching pad mode while a pad is held releases it once; letting go of the pad afterwards sends nothing")
    func modeSwitchReleasesHeldPad() throws {
        let rig = try Self.startedRig()
        Self.down(rig, 32)
        rig.osc.sent.removeAll()

        Self.press(rig, Self.modeRoll)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])

        rig.osc.sent.removeAll()
        Self.up(rig, 32)
        #expect(rig.osc.sent == [])
    }

    @Test("Switching pad mode releases only the pads, not a held Cue")
    func modeSwitchKeepsOtherHolds() throws {
        let rig = try Self.startedRig()
        Self.down(rig, 2)     // Cue held
        Self.down(rig, 33)    // pad 2 held
        rig.osc.sent.removeAll()
        Self.press(rig, Self.modeLoop)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(2), .int(0)])])
    }

    @Test("Held pads are in the held-control list: stop releases a held roll once")
    func stopReleasesHeldPad() throws {
        let rig = try Self.startedRig()
        Self.press(rig, Self.modeRoll)
        Self.down(rig, 33)
        rig.osc.sent.removeAll()

        rig.coordinator.stop()
        Self.up(rig, 33)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/SlipLoop/Sixteenth", [.int(0)])])
    }

    /// The mode button LEDs: Hot Cue, Roll, Slicer, Loop (notes 27-30).
    static func modeLEDs(_ rig: Rig) -> [UInt8?] {
        [rig.leds[27], rig.leds[28], rig.leds[29], rig.leds[30]]
    }

    @Test("The mode button LEDs show the current mode: full (127) for it, dim (1) for the rest")
    func modeLEDsShowMode() throws {
        let rig = try Self.startedRig()
        #expect(Self.modeLEDs(rig) == [127, 1, 1, 1])

        Self.press(rig, Self.modeRoll)
        #expect(Self.modeLEDs(rig) == [1, 127, 1, 1])

        Self.press(rig, Self.modeLoop)
        #expect(Self.modeLEDs(rig) == [1, 1, 1, 127])
    }

    /// The eight pad LEDs, notes 32-39.
    static func padLEDs(_ rig: Rig) -> [UInt8?] {
        (UInt8(32)...39).map { rig.leds[$0] }
    }

    /// Syndicate's Cues feedback: a color slot and a name for each of the 8 hot cues (slot 0 is an empty cue).
    static func cues(_ slots: [Int32], deck: Int = 1) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/\(deck)/Cues", slots.flatMap { [OSCArgument.int($0), .string($0 == 0 ? "" : "Cue")] })
    }

    @Test("Hot cue pads show their cue colors from Syndicate's default palette: red 48, orange 56, empty off")
    func cueColorsDefaultPalette() throws {
        let rig = try Self.startedRig()
        #expect(Self.padLEDs(rig) == [0, 0, 0, 0, 0, 0, 0, 0])

        // Slot 1 is red (255, 0, 0): 0b11_00_00 = 48. Slot 2 is orange (255, 128, 0): 0b11_10_00 = 56.
        rig.coordinator.feedback(Self.cues([1, 0, 2, 0, 0, 0, 0, 0]))
        #expect(Self.padLEDs(rig) == [48, 0, 56, 0, 0, 0, 0, 0])
    }
}
