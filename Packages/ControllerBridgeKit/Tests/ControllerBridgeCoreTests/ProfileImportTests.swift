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

    @Test("device_hints needs at least one non-empty name, or no device would ever match after the next replug (#93)")
    func deviceHintsNotEmpty() {
        #expect(throws: MappingError.invalid(["device_hints: needs at least one device name"])) {
            try Self.importing(#"{"device_hints": []}"#)
        }
        #expect(throws: MappingError.invalid(["device_hints[1]: can't be empty"])) {
            try Self.importing(#"{"device_hints": ["LC6000", " "]}"#)
        }
    }

    @Test("Keys Settings owns (OSC addresses, Deck, Channel) aren't applied from a file, and are named so the DJ knows (#93)")
    func settingsOwnedKeys() throws {
        let file = #"{"mapping": {"osc": {"port": 9191, "root": "/Syndicate/"}, "deck": {"number": 3}, "notes": {"play": 60}}}"#
        let profile = try Self.importing(file)
        #expect(profile.mapping.osc.port == 9090)
        #expect(profile.mapping.deck.number == 1)
        #expect(profile.mapping.notes.buttons["play"] == 60)
        #expect(ControllerProfile.settingsOwnedKeys(in: Data(file.utf8)) == ["mapping.osc.port", "mapping.deck.number"])
        #expect(ControllerProfile.settingsOwnedKeys(in: Data(#"{"mapping": {"notes": {"play": 60}}}"#.utf8)) == [])
    }

    @Test("Export leaves out the keys Settings owns, so editing them in a file can't look like it worked; it still round-trips")
    func exportOmitsSettingsOwned() throws {
        let profile = try Self.importing(#"{"mapping": {"notes": {"play": 60}}}"#)
        let exported = try profile.exported()
        let object = try #require(try JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let mapping = try #require(object["mapping"] as? [String: Any])
        let osc = try #require(mapping["osc"] as? [String: Any])
        for key in ["host", "port", "feedback_host", "feedback_port"] { #expect(osc[key] == nil, "osc.\(key)") }
        #expect(osc["root"] as? String == "/Syndicate/")
        #expect(mapping["deck"] == nil)
        let midi = try #require(mapping["midi"] as? [String: Any])
        #expect(midi["channel"] == nil)
        #expect(midi["input"] as? String == "LC6000")
        #expect(try Self.importing(String(decoding: exported, as: UTF8.self)) == profile)
    }

    @Test("The import note says Settings owns Deck, Channel and the OSC addresses, and names any the file set")
    func importNote() {
        #expect(ControllerProfile.importNote(file: "mine.json", settingsOwned: []) ==
            "Imported mine.json. Deck, Channel and the OSC addresses come from Settings.")
        #expect(ControllerProfile.importNote(file: "mine.json", settingsOwned: ["mapping.osc.port", "mapping.deck.number"]) ==
            "Imported mine.json. Deck, Channel and the OSC addresses come from Settings, so the file's osc.port and deck.number weren't applied.")
        #expect(ControllerProfile.importNote(file: "mine.json", settingsOwned: ["mapping.midi.channel"]) ==
            "Imported mine.json. Deck, Channel and the OSC addresses come from Settings, so the file's midi.channel wasn't applied.")
    }

    @Test("An import is checked against the profile it names: a key that profile doesn't have is unknown (#94)")
    func schemaPerProfile() throws {
        var mapping = try Mapping.bundledDefault()
        mapping.notes.buttons["vinyl"] = nil
        let pad = ControllerProfile(id: "no-vinyl", name: "No Vinyl", deviceHints: ["NV"], mapping: mapping)
        let bundled = try ControllerProfile.bundled() + [pad]
        let file = Data(#"{"mapping": {"notes": {"vinyl": 120}}}"#.utf8)
        #expect(throws: MappingError.invalid(["mapping.notes.vinyl: unknown key"])) {
            try ControllerProfile.importing(file, bundled: bundled, active: "no-vinyl")
        }
        #expect(try ControllerProfile.importing(file, bundled: bundled, active: "denon-lc6000-prime").mapping.notes.buttons["vinyl"] == 120)
    }
}
