import Foundation
@testable import ControllerBridgeCore
import Testing

/// Shift done in hardware (#226): notes.shifted names the note a button sends with Shift held, as the DDJ-400 and the
/// MCX8000 do. Left out or empty, the app works Shift out itself, as on the LC6000.
@Suite("Hardware Shift mapping")
struct HardwareShiftMappingTests {
    @Test("Left out it's empty; the bundled LC6000 has none; a button is named with its shifted note")
    func decoding() throws {
        let notes = try JSONDecoder().decode(Mapping.Notes.self, from: Data(#"{ "play": 1, "pads": [32] }"#.utf8))
        #expect(notes.shifted == [:])
        #expect(notes.buttons == ["play": 1])
        #expect(try Mapping.bundledDefault().notes.shifted == [:])
        let shifted = try JSONDecoder().decode(Mapping.Notes.self, from: Data(#"{ "play": 1, "pads": [32], "shifted": { "play": 4 } }"#.utf8))
        #expect(shifted.shifted == ["play": 4])
        #expect(shifted.buttons == ["play": 1])
    }
}
