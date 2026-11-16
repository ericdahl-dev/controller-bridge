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

/// The LED sweep's button pass (#194): each note steps through the profile's full, dim and off.
@Suite("LED levels in the sweep")
struct LEDLevelsSweepTests {
    /// The velocities note 0 (a button note on both profiles) gets during a sweep, 0.03 s a step.
    static func note0(_ override: String?) throws -> [UInt8] {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.coordinator.startLEDSweep(delay: 0.03)
        // 64 color steps, then note 0's full, dim and off a third of a step apart.
        for step in 1...80 {
            rig.clock.now = Double(step) * 0.03
            rig.coordinator.tick()
        }
        return (rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? []).compactMap {
            if case let .noteOn(_, 0, velocity) = $0 { return velocity } else { return nil }
        }
    }

    @Test("A test-only profile sweeps a button at 100, 20, then 5")
    func profileLevels() throws {
        #expect(try Self.note0(#"{ "leds": { "levels": { "full": 100, "dim": 20, "off": 5 } } }"#) == [100, 20, 5])
    }

    @Test("The LC6000 sweeps a button at 127, 1, then 0, as before")
    func lc6000() throws {
        #expect(try Self.note0(nil) == [127, 1, 0])
    }
}

/// The import check (#194): each level is a velocity, 0-127, in plain words.
@Suite("LED levels in the import check")
struct LEDLevelsImportTests {
    static func importing(_ json: String) throws -> ControllerProfile {
        try ControllerProfile.importing(Data(json.utf8), bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
    }

    @Test("A level out of 0-127, the wrong kind, or an unknown member is named")
    func problems() {
        #expect(throws: MappingError.invalid([
            "mapping.leds.levels.dim: 300 is out of range, expected 0-127",
            "mapping.leds.levels.full: expected a whole number, got \"max\"",
            "mapping.leds.levels.bright: unknown key",
        ])) {
            try Self.importing(#"{"mapping": {"leds": {"levels": {"dim": 300, "full": "max", "bright": 64}}}}"#)
        }
    }

    @Test("A partial override imports and keeps the other levels")
    func partial() throws {
        #expect(try Self.importing(#"{"mapping": {"leds": {"levels": {"dim": 20}}}}"#).mapping.leds.levels == .init(full: 127, dim: 20, off: 0))
    }
}
