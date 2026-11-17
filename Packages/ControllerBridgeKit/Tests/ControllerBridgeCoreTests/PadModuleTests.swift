import Foundation
@testable import ControllerBridgeCore
import Testing

/// The pads as a module (#383 slice 5): plain values in, sends out; the Bridge applies them.
@Suite("Pad module: mode")
struct PadModuleModeTests {
    static let lc6000 = try! Mapping.bundledDefault()

    /// A profile with one cycling mode button (#198) and notes per mode (#225).
    static func ddj() throws -> Mapping {
        let json = #"""
            { "notes": { "mode_cycle": 108 }, "pads": { "mode_select": "cycle",
                        "mode_notes": { "hotcue": [32, 33, 34, 35, 36, 37, 38, 39], "roll": [112, 113, 114, 115, 116, 117, 118, 119],
                                        "loop": [96, 97, 98, 99, 100, 101, 102, 103], "slicer": [120, 121, 122, 123, 124, 125, 126, 127] } } }
            """#
        return try Mapping.bundledDefault(overriddenBy: Data(json.utf8))
    }

    @Test("A mode button lets held pads go, then switches")
    func modeButton() {
        var pads = PadModule(mapping: Self.lc6000)
        #expect(pads.mode == .hotCue)
        #expect(pads.modeButton(.roll) == [.releasePads])
        #expect(pads.mode == .roll)
    }

    @Test("The cycle button goes Hot Cue → Roll → Loop → Slicer → Hot Cue on a cycle profile; the LC6000's does nothing")
    func cycle() throws {
        var pads = PadModule(mapping: try Self.ddj())
        var seen: [PadMode] = []
        for _ in 0..<4 {
            _ = pads.cycle()
            seen.append(pads.mode)
        }
        #expect(seen == [.roll, .loop, .slicer, .hotCue])
        var lc6000 = PadModule(mapping: Self.lc6000)
        #expect(lc6000.cycle() == [])
        #expect(lc6000.mode == .hotCue)
    }

    @Test("A note from another mode's list (#225) switches to that mode, letting held pads go, and plays that pad")
    func modeNotes() throws {
        var pads = PadModule(mapping: try Self.ddj())
        let press = pads.press(note: 114)
        #expect(press?.index == 2)
        #expect(press?.sends == [.releasePads])
        #expect(pads.mode == .roll)
        let again = pads.press(note: 115)
        #expect(again?.sends == [], "same mode: nothing to let go")
        #expect(pads.press(note: 1) == nil, "not a pad: Play")
        #expect(pads.notes(for: .loop) == [96, 97, 98, 99, 100, 101, 102, 103])
    }

    @Test("A settings swap carries the pad mode to the new bridge's module (#115)")
    func carry() {
        var old = PadModule(mapping: Self.lc6000)
        _ = old.modeButton(.loop)
        var new = PadModule(mapping: Self.lc6000)
        new.carry(from: old)
        #expect(new.mode == .loop)
    }

    @Test("Without notes per mode, notes.pads plays in every mode")
    func plainPads() {
        var pads = PadModule(mapping: Self.lc6000)
        #expect(pads.press(note: 32)?.index == 0)
        #expect(pads.notes(for: .roll) == Self.lc6000.notes.pads)
    }
}

@Suite("Pad module: what a press does")
struct PadModuleActionTests {
    static let lc6000 = PadModuleModeTests.lc6000
    static let still = PadModule.Facts(shift: false, playing: true, playPending: false)

    @Test("Hot Cue: hold HotCue n 1, release n 0; a pad past Syndicate's 8 cues does nothing")
    func hotCue() {
        let pads = PadModule(mapping: Self.lc6000)
        #expect(pads.pressed(2, Self.still) == [.hold(2, "HotCue", press: [.int(3), .int(1)], release: [.int(3), .int(0)])])
        #expect(pads.released(2) == [.release(2)])
        #expect(pads.pressed(8, Self.still) == [])
    }

    @Test("Shift on a stopped deck: the cue jump (#358), not a hot cue; playing, or a start pending, it's a hot cue")
    func shiftStopped() {
        let pads = PadModule(mapping: Self.lc6000)
        #expect(pads.pressed(1, PadModule.Facts(shift: true, playing: false, playPending: false)) == [.cueJump(2)])
        #expect(pads.pressed(1, PadModule.Facts(shift: true, playing: true, playPending: false))
            == [.hold(1, "HotCue", press: [.int(2), .int(1)], release: [.int(2), .int(0)])])
        #expect(pads.pressed(1, PadModule.Facts(shift: true, playing: false, playPending: true))
            == [.hold(1, "HotCue", press: [.int(2), .int(1)], release: [.int(2), .int(0)])])
    }

    @Test("Roll: hold the pad's slip loop size (#196). Loop: SetCueLoop n. Slicer: nothing")
    func otherModes() {
        var pads = PadModule(mapping: Self.lc6000)
        _ = pads.modeButton(.roll)
        #expect(pads.pressed(0, Self.still) == [.hold(0, "SlipLoop/ThirtySecond", press: [.int(1)], release: [.int(0)])])
        #expect(pads.pressed(7, Self.still) == [.hold(7, "SlipLoop/Four", press: [.int(1)], release: [.int(0)])])
        _ = pads.modeButton(.loop)
        #expect(pads.pressed(4, Self.still) == [.osc("SetCueLoop", .int(5))])
        _ = pads.modeButton(.slicer)
        #expect(pads.pressed(0, Self.still) == [])
    }
}
