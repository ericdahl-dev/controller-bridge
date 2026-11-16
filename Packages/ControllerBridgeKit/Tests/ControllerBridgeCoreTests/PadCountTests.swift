import Foundation
@testable import ControllerBridgeCore
import Testing

/// Pad count and roll sizes from the profile (#196): 4, 8 or 16 pads, and the roll each pad plays.
@Suite("Pad count mapping")
struct PadCountMappingTests {
    @Test("Left out, the roll sizes are the LC6000's eight, 1/32 up to 4 beats")
    func defaultRollSizes() throws {
        var body = try #require(try JSONSerialization.jsonObject(with: Mapping.defaultMappingJSON()) as? [String: Any])
        body["pads"] = nil
        let mapping = try JSONDecoder().decode(Mapping.self, from: JSONSerialization.data(withJSONObject: body))
        #expect(mapping.pads.rollSizes == ["ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four"])
    }

    @Test("The bundled LC6000 has 8 pads and the eight roll sizes, as before #196")
    func lc6000() throws {
        let mapping = try Mapping.bundledDefault()
        #expect(mapping.notes.pads.count == 8)
        #expect(mapping.pads.rollSizes == ["ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four"])
    }
}
