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
}
