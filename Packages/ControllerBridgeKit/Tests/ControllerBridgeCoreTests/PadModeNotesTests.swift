import Foundation
@testable import ControllerBridgeCore
import Testing

/// Pad notes per pad mode (#225): on Pioneer controllers each pad mode sends its own note range for the same pads.
@Suite("Pad mode notes mapping")
struct PadModeNotesMappingTests {
    @Test("Left out (the bundled LC6000), notes.pads serves every mode")
    func lc6000() throws {
        #expect(try Mapping.bundledDefault().pads.modeNotes == nil)
    }

    @Test("A profile lists each mode's notes, one per pad")
    func decodes() throws {
        let json = #"{ "mode_notes": { "hotcue": [0, 1], "roll": [16, 17], "loop": [96, 97], "slicer": [32, 33] } }"#
        let pads = try JSONDecoder().decode(Mapping.Pads.self, from: Data(json.utf8))
        #expect(pads.modeNotes == Mapping.Pads.ModeNotes(hotcue: [0, 1], roll: [16, 17], loop: [96, 97], slicer: [32, 33]))
    }
}

/// The Coordinator seam (#225): a test-only profile whose pads send Hot Cue 32-39 (the LC6000's pad notes),
/// Roll 100-107, Loop 108-115 and Slicer 116-123, all free in the LC6000 mapping.
@Suite("Pad mode notes at the Coordinator")
struct PadModeNotesCoordinatorTests {
    static let override = #"""
        { "pads": { "mode_notes": { "hotcue": [32, 33, 34, 35, 36, 37, 38, 39], "roll": [100, 101, 102, 103, 104, 105, 106, 107],
                                    "loop": [108, 109, 110, 111, 112, 113, 114, 115], "slicer": [116, 117, 118, 119, 120, 121, 122, 123] } } }
        """#

    static func started(_ override: String?) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func press(_ rig: Rig, _ note: UInt8) -> [OSCMessage] {
        rig.osc.sent.removeAll()
        PadsTests.press(rig, note)
        return rig.osc.sent
    }

    @Test("The note says the mode: Roll's 100 plays a 1/32 roll, Loop's 108 sets cue loop 1, Hot Cue's 32 holds hot cue 1, Slicer's 116 nothing")
    func noteSaysMode() throws {
        let rig = try Self.started(Self.override)
        #expect(Self.press(rig, 100) == [OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(1)]),
                                         OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(0)])])
        #expect(Self.press(rig, 108) == [OSCMessage("/Syndicate/Deck/1/SetCueLoop", [.int(1)])])
        #expect(Self.press(rig, 39) == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(8), .int(1)]),
                                        OSCMessage("/Syndicate/Deck/1/HotCue", [.int(8), .int(0)])])
        #expect(Self.press(rig, 116) == [])
    }

    @Test("A held hot cue is let go when a roll note arrives, before the roll starts")
    func modeChangeReleases() throws {
        let rig = try Self.started(Self.override)
        PadsTests.down(rig, 32)
        rig.osc.sent.removeAll()
        PadsTests.down(rig, 101)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)]),
                                 OSCMessage("/Syndicate/Deck/1/SlipLoop/Sixteenth", [.int(1)])])
    }
}
