import ControllerBridgeCore
import Foundation
import Testing

/// The full mapping check (#24): every problem in a mapping body, by key path, in document order. The bundled
/// default mapping is the schema. Bodies here are partial overrides, as a user's import is.
@Suite("Mapping check")
struct MappingCheckTests {
    static func problems(_ json: String) -> [String] {
        Mapping.problems(in: Data(json.utf8))
    }

    @Test("A key the default mapping doesn't have is unknown, named by its path; a typo isn't silently a new button")
    func unknownKeys() {
        #expect(Self.problems(#"{"notes": {"paly": 1}}"#) == ["notes.paly: unknown key"])
        #expect(Self.problems(#"{"lights": {}, "deck": {"number": 2, "side": "left"}}"#) == [
            "lights: unknown key",
            "deck.side: unknown key",
        ])
    }

    @Test("The default mapping itself has no problems")
    func defaultIsClean() throws {
        #expect(Mapping.problems(in: try Mapping.defaultMappingJSON()) == [])
    }
}
