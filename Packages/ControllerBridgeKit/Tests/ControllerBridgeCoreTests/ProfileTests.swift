import ControllerBridgeCore
import Foundation
import Testing

/// Controller profiles (#43): a named mapping plus the device name hints that pick it.
@Suite("Controller profiles")
struct ProfileTests {
    @Test("The app ships one profile, Denon LC6000 PRIME, matched by \"LC6000\", whose mapping is today's default")
    func bundledLC6000Profile() throws {
        let profiles = try ControllerProfile.bundled()
        #expect(profiles.map(\.id) == ["denon-lc6000-prime"])
        let lc6000 = try #require(profiles.first)
        #expect(lc6000.name == "Denon LC6000 PRIME")
        #expect(lc6000.deviceHints == ["LC6000"])
        // MappingTests pins every value of the default mapping by literal; this pins that the profile carries it.
        #expect(lc6000.mapping == (try Mapping.bundledDefault()))
        #expect(lc6000.mapping.notes.buttons["play"] == 1)
        #expect(lc6000.mapping.leds.ring == 40)
    }

    /// A test-only profile for a made-up controller: MIDI channel 2, Play on note 60.
    static func testPadFile() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "test-pad", withExtension: "json", subdirectory: "Resources"))
        return try Data(contentsOf: url)
    }

    @Test("A new controller is a new profile file: Test Pad decodes with its own id, name, hints and mapping")
    func secondProfileIsAFile() throws {
        let testPad = try ControllerProfile(decoding: Self.testPadFile())
        #expect(testPad.id == "test-pad")
        #expect(testPad.name == "Test Pad")
        #expect(testPad.deviceHints == ["TP-1"])
        #expect(testPad.mapping.midi.channel == 2)
        #expect(testPad.mapping.notes.buttons["play"] == 60)
    }

    @Test("A profile whose mapping breaks a rule is refused with the same readable error as a mapping")
    func badProfileRefused() throws {
        var profile = try #require(try JSONSerialization.jsonObject(with: Self.testPadFile()) as? [String: Any])
        var mapping = try #require(profile["mapping"] as? [String: Any])
        mapping["midi"] = ["input": "TP-1", "output": "TP-1", "channel": 0]
        profile["mapping"] = mapping
        let data = try JSONSerialization.data(withJSONObject: profile)
        #expect(throws: MappingError.invalid(["midi.channel: 0 is out of range, expected 1-16"])) {
            try ControllerProfile(decoding: data)
        }
    }
}
