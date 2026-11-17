import Foundation
@testable import ControllerBridgeCore
import Testing

/// A controller that lacks a control leaves its section out (#341): the DDJ-400 has no needle strip. The profile
/// loads, and nothing is listened for or sent for the missing control.
@Suite("Optional sections")
struct OptionalSectionsTests {
    /// The bundled LC6000 as a whole profile file, without `sections`.
    static func profile(without sections: [String]) throws -> ControllerProfile {
        var mapping = try JSONSerialization.jsonObject(with: Mapping.defaultMappingJSON()) as! [String: Any]
        for section in sections { mapping[section] = nil }
        let file: [String: Any] = ["id": "test-lc6000-lite", "name": "Test lite", "device_hints": ["LC6000"], "mapping": mapping]
        return try ControllerProfile(decoding: JSONSerialization.data(withJSONObject: file, options: .sortedKeys))
    }

    static func rig(_ profile: ControllerProfile) -> Rig {
        let rig = Rig(mapping: profile.mapping)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("No needle: the profile loads, and the LC6000's needle CCs and touch note send nothing")
    func noNeedle() throws {
        let profile = try Self.profile(without: ["needle"])
        #expect(profile.mapping.needle == nil)
        let rig = Self.rig(profile)
        rig.coordinator.midi(.noteOn(channel: 0, note: 70, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.controlChange(channel: 0, controller: 64, value: 40), source: Rig.lc6000.id)
        rig.coordinator.midi(.controlChange(channel: 0, controller: 65, value: 0), source: Rig.lc6000.id)
        #expect(rig.osc.sent == [])
    }

    @Test("The LC6000 still has its needle: CCs 64 and 65, touch note 70")
    func lc6000Needle() throws {
        let needle = try #require(try Mapping.bundledDefault().needle)
        #expect(needle.msbCC == 64 && needle.lsbCC == 65 && needle.touchNote == 70)
    }
}
