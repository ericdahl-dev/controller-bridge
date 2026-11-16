import Foundation
@testable import ControllerBridgeCore
import Testing

/// Button LED levels from the profile (#194): full, dim and off, the LC6000's 127, 1 and 0 unless a profile says.
@Suite("LED levels")
struct LEDLevelsTests {
    @Test("Left out, the levels are the LC6000's 127, 1 and 0; a partial override keeps the rest")
    func decoding() throws {
        #expect(try JSONDecoder().decode(Mapping.LEDLevels.self, from: Data("{}".utf8)) == .init(full: 127, dim: 1, off: 0))
        #expect(try JSONDecoder().decode(Mapping.LEDLevels.self, from: Data(#"{"dim": 20}"#.utf8)) == .init(full: 127, dim: 20, off: 0))
    }

    @Test("The bundled LC6000 is 127, 1 and 0, as before #194")
    func lc6000() throws {
        #expect(try Mapping.bundledDefault().leds.levels == .init(full: 127, dim: 1, off: 0))
    }
}

/// The Coordinator seam (#194): a test-only profile whose buttons light at 100, dim at 20 and go off at 5. Key Lock
/// (note 22) is the bridge's own state; its LED is dim until pressed.
@Suite("LED levels at the Coordinator")
struct LEDLevelsCoordinatorTests {
    static let levels = #""levels": { "full": 100, "dim": 20, "off": 5 }"#

    static func started(_ leds: String) throws -> Rig {
        let rig = try Rig(override: #"{ "leds": { \#(leds) } }"#)
        rig.coordinator.start()
        return rig
    }

    static func press(_ rig: Rig, _ note: UInt8) {
        rig.coordinator.midi(.noteOn(channel: 0, note: note, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOff(channel: 0, note: note, velocity: 0), source: Rig.lc6000.id)
    }

    @Test("Key Lock is dim (20) until pressed, then full (100), then dim again")
    func fullAndDim() throws {
        let rig = try Self.started(Self.levels)
        #expect(rig.leds[22] == 20)
        Self.press(rig, 22)
        #expect(rig.leds[22] == 100)
        Self.press(rig, 22)
        #expect(rig.leds[22] == 20)
    }

    @Test("With dim_unlit_buttons off, an unlit button is the profile's off (5), not 0")
    func off() throws {
        let rig = try Self.started(Self.levels + #", "dim_unlit_buttons": false"#)
        #expect(rig.leds[22] == 5)
    }

    @Test("Turning the LEDs off sends a button the profile's off (5), and a pad 0, its no-color")
    func ledsOff() throws {
        let rig = try Self.started(Self.levels)
        Self.press(rig, 22)                                  // Key Lock lit at 100
        rig.coordinator.setLEDs(enabled: false)
        #expect(rig.leds[22] == 5)
    }

    @Test("The LC6000 is unchanged: Key Lock 1, then 127, and 0 with dim_unlit_buttons off")
    func lc6000() throws {
        let rig = try Self.started(#""stale_idle": "dim""#)
        #expect(rig.leds[22] == 1)
        Self.press(rig, 22)
        #expect(rig.leds[22] == 127)
        #expect(try Self.started(#""dim_unlit_buttons": false"#).leds[22] == 0)
    }
}
