import ControllerBridgeCore
import Foundation
import Testing

/// Importing a mapping file (#24): it overrides a bundled profile. Every field is optional; `id`, if given, must name a
/// bundled profile, and a missing one means the active profile. The mapping merges over the bundled body.
@Suite("Profile import")
struct ProfileImportTests {
    static func importing(_ json: String) throws -> ControllerProfile {
        try ControllerProfile.importing(Data(json.utf8), bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
    }

    @Test("A good file overrides the active profile: its name and one note change, the rest is the bundled profile")
    func goodImport() throws {
        let profile = try Self.importing(#"{"name": "My LC6000", "mapping": {"notes": {"play": 60}}}"#)
        let bundled = try #require(try ControllerProfile.bundled().first)
        #expect(profile.id == "denon-lc6000-prime")
        #expect(profile.name == "My LC6000")
        #expect(profile.deviceHints == ["LC6000"])
        #expect(profile.mapping.notes.buttons["play"] == 60)
        #expect(profile.mapping.notes.buttons["cue"] == bundled.mapping.notes.buttons["cue"])
        #expect(profile.mapping.leds == bundled.mapping.leds)
    }

    @Test("An id that isn't a bundled profile is refused: v1 adds controllers only as bundled files")
    func unknownID() {
        #expect(throws: MappingError.invalid([#"id: "ddj-flx4" isn't a bundled profile (denon-lc6000-prime)"#])) {
            try Self.importing(#"{"id": "ddj-flx4", "mapping": {}}"#)
        }
    }

    @Test("A bad file throws every problem at once, with paths from the top of the file")
    func badImport() {
        #expect(throws: MappingError.invalid([
            "name: expected text, got 5",
            "mapping.notes.paly: unknown key",
            "mapping.midi.channel: 0 is out of range, expected 1-16",
            "theme: unknown key",
        ])) {
            try Self.importing(#"{"name": 5, "mapping": {"notes": {"paly": 1}, "midi": {"channel": 0}}, "theme": "dark"}"#)
        }
    }

    @Test("Export writes the whole merged profile, and importing it gives the same profile back")
    func exportRoundTrips() throws {
        let edited = try Self.importing(#"{"name": "My LC6000", "device_hints": ["LC6000", "PRIME"], "mapping": {"notes": {"play": 60}, "jog": {"msb_cc": 18, "lsb_cc": 50}, "leds": {"beat_pulse": "downbeat"}}}"#)
        let exported = try edited.exported()
        #expect(try Self.importing(String(decoding: exported, as: UTF8.self)) == edited)
        // Whole, not a diff: a value left at its default is written too.
        let object = try #require(try JSONSerialization.jsonObject(with: exported) as? [String: Any])
        #expect(object["id"] as? String == "denon-lc6000-prime")
        #expect(((object["mapping"] as? [String: Any])?["notes"] as? [String: Any])?["cue"] as? Int == 2)
    }
}
