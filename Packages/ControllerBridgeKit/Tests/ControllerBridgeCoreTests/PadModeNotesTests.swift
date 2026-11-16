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

    /// Roll's pad color (255, 140, 0) by hand: 3, 2, 0 → 0b00111000 = 56. Slot 1 red → 48.
    @Test("The pad LEDs light the current mode's notes: Hot Cue's 32 red, then in Roll 100-107 orange and 32 dark")
    func ledsFollowMode() throws {
        let rig = try Self.started(Self.override)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Cues", [.int(1), .string("c1")]))
        #expect(rig.leds[32] == 48)
        #expect(rig.leds[100] == 0)
        PadsTests.press(rig, PadsTests.modeRoll)
        #expect((100...107).map { rig.leds[UInt8($0)] } == Array(repeating: 56, count: 8))
        #expect(rig.leds[32] == 0)
    }
}

/// The LC6000 is unchanged by #225: no notes per mode, so its pads keep their notes and the mode buttons decide.
@Suite("Pad mode notes: the LC6000 unchanged")
struct PadModeNotesLC6000Tests {
    @Test("In Roll mode its pad 1 (32) still plays a 1/32 roll, lit orange (56); note 100 is nothing")
    func lc6000() throws {
        let rig = try PadModeNotesCoordinatorTests.started(nil)
        PadsTests.press(rig, PadsTests.modeRoll)
        #expect(PadModeNotesCoordinatorTests.press(rig, 32) == [OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(1)]),
                                                               OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(0)])])
        #expect(rig.leds[32] == 56)
        #expect(PadModeNotesCoordinatorTests.press(rig, 100) == [])
        #expect(rig.leds[100] == nil)
    }
}

/// The import check and decoder (#225), in plain words.
@Suite("Pad mode notes in the import check")
struct PadModeNotesImportTests {
    static let eight = "[100, 101, 102, 103, 104, 105, 106, 107]"

    static func importing(_ modeNotes: String) throws {
        _ = try ControllerProfile.importing(Data(#"{"mapping": {"pads": {"mode_notes": \#(modeNotes)}}}"#.utf8),
                                            bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
    }

    static func four(roll: String = eight) -> String {
        #"{"hotcue": [32, 33, 34, 35, 36, 37, 38, 39], "roll": \#(roll), "loop": [108, 109, 110, 111, 112, 113, 114, 115], "slicer": [116, 117, 118, 119, 120, 121, 122, 123]}"#
    }

    @Test("An unknown mode is named")
    func unknownMode() {
        #expect(throws: MappingError.invalid(["mapping.pads.mode_notes.beatjump: unknown key"])) {
            try Self.importing(#"{"beatjump": [40]}"#)
        }
    }

    @Test("Each note is 0-127")
    func noteRange() {
        #expect(throws: MappingError.invalid(["mapping.pads.mode_notes.roll[0]: 200 is out of range, expected 0-127"])) {
            try Self.importing(Self.four(roll: "[200, 101, 102, 103, 104, 105, 106, 107]"))
        }
    }

    @Test("Each mode has one note per pad")
    func countMatches() {
        #expect(throws: MappingError.invalid(["pads.mode_notes.roll: 7 notes, but there are 8 pads (notes.pads)"])) {
            try Self.importing(Self.four(roll: "[100, 101, 102, 103, 104, 105, 106]"))
        }
    }

    @Test("Every mode is listed")
    func missingMode() {
        #expect(throws: MappingError.invalid(["pads.mode_notes: slicer is missing (list all four modes)"])) {
            try Self.importing(#"{"hotcue": [32, 33, 34, 35, 36, 37, 38, 39], "roll": \#(Self.eight), "loop": [108, 109, 110, 111, 112, 113, 114, 115]}"#)
        }
    }

    @Test("A good import with all four modes works")
    func good() throws {
        try Self.importing(Self.four())
    }
}
