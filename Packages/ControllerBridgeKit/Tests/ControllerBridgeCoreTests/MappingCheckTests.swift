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

    @Test("A value of the wrong kind names what was expected and what was found")
    func wrongTypes() {
        #expect(Self.problems(#"{"pitch": {"invert": 1}}"#) == ["pitch.invert: expected true or false, got 1"])
        #expect(Self.problems(#"{"midi": {"channel": 1.5, "input": 5}}"#) == [
            "midi.channel: expected a whole number, got 1.5",
            "midi.input: expected text, got 5",
        ])
        #expect(Self.problems(#"{"jog": {"ccs": 55, "dead": 1}, "pitch": {"dead_zone": "small"}}"#) == [
            "jog.ccs: expected a list, got 55",
            "jog.dead: unknown key",
            "pitch.dead_zone: expected a number, got \"small\"",
        ])
        #expect(Self.problems(#"{"notes": {"pads": [32, "x"]}, "deck": 2}"#) == [
            "notes.pads[1]: expected a whole number, got \"x\"",
            "deck: expected an object, got 2",
        ])
    }

    @Test("A whole number written as 2.0 is still a whole number; a fractional setting accepts a whole number")
    func numberForms() {
        #expect(Self.problems(#"{"deck": {"number": 2.0}, "pitch": {"dead_zone": 0}}"#) == [])
    }
}
