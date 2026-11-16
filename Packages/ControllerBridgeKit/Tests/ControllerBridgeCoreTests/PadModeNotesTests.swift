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
