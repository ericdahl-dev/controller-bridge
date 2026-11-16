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

/// notes.shifted through save and the import check (#226).
@Suite("Hardware Shift round trip")
struct HardwareShiftRoundTripTests {
    @Test("The LC6000 encodes no shifted key, so a saved profile still reads the same")
    func noKeyWhenEmpty() throws {
        let data = try JSONEncoder().encode(Mapping.bundledDefault().notes)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["shifted"] == nil)
    }

    @Test("A profile naming shifted buttons imports, and keeps them")
    func imports() throws {
        let profile = try ControllerProfile.importing(Data(#"{"mapping": {"notes": {"shifted": {"play": 110, "beat_jump_back": 60}}}}"#.utf8),
                                                      bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
        #expect(profile.mapping.notes.shifted == ["play": 110, "beat_jump_back": 60])
    }
}
