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
}
