import Foundation
@testable import ControllerBridgeCore
import Testing

/// One pad-mode button that cycles the modes (#198), instead of the LC6000's four mode buttons.
@Suite("Pad mode select mapping")
struct PadModeSelectMappingTests {
    @Test("Left out, a profile selects pad modes with four buttons, as the LC6000 does")
    func defaultButtons() throws {
        var body = try #require(try JSONSerialization.jsonObject(with: Mapping.defaultMappingJSON()) as? [String: Any])
        var pads = try #require(body["pads"] as? [String: Any])
        pads["mode_select"] = nil
        body["pads"] = pads
        let mapping = try JSONDecoder().decode(Mapping.self, from: JSONSerialization.data(withJSONObject: body))
        #expect(mapping.pads.modeSelect == .buttons)
        #expect(mapping.pads.modeCycleVelocities == nil)
    }

    @Test("The bundled LC6000 names its four buttons, and has no cycle velocities")
    func lc6000() throws {
        let mapping = try Mapping.bundledDefault()
        #expect(mapping.pads.modeSelect == .buttons)
        #expect(mapping.pads.modeCycleVelocities == nil)
        let body = try #require(try JSONSerialization.jsonObject(with: Mapping.defaultMappingJSON()) as? [String: Any])
        let pads = try #require(body["pads"] as? [String: Any])
        #expect(pads["mode_select"] as? String == "buttons", "the bundled file states the default")
    }

    @Test("A cycling profile decodes its mode and its button LED's velocity per mode")
    func cycle() throws {
        let json = #"{ "mode_select": "cycle", "mode_cycle_velocities": { "hotcue": 127, "roll": 64, "loop": 32, "slicer": 1 } }"#
        let pads = try JSONDecoder().decode(Mapping.Pads.self, from: Data(json.utf8))
        #expect(pads.modeSelect == .cycle)
        #expect(pads.modeCycleVelocities == Mapping.Pads.ModeVelocities(hotcue: 127, roll: 64, loop: 32, slicer: 1))
        #expect(pads.rollSizes == Mapping.Pads.lc6000RollSizes)
    }
}

/// The Coordinator seam (#198): a test-only profile with one cycling button on note 120, free in the LC6000 mapping.
/// The LC6000's four mode notes (27-30) stay mapped, as indicator LEDs here.
@Suite("Pad mode cycle at the Coordinator")
struct PadModeCycleCoordinatorTests {
    static let cycleNote: UInt8 = 120
    static let cycling = #"{ "notes": { "mode_cycle": 120 }, "pads": { "mode_select": "cycle" } }"#
    static let cyclingLit = #"""
        { "notes": { "mode_cycle": 120 },
          "pads": { "mode_select": "cycle", "mode_cycle_velocities": { "hotcue": 127, "roll": 64, "loop": 32, "slicer": 1 } } }
        """#

    static func started(_ override: String?) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    /// What pad 1 sends when pressed and released.
    static func pad1(_ rig: Rig) -> [OSCMessage] {
        rig.osc.sent.removeAll()
        PadsTests.press(rig, PadsTests.pad1)
        return rig.osc.sent
    }

    @Test("Each press of the cycle button moves pad 1 on: hot cue, roll, cue loop, slicer (nothing), then hot cue again")
    func cycles() throws {
        let rig = try Self.started(Self.cycling)
        #expect(Self.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(1)]),
                                   OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])
        PadsTests.press(rig, Self.cycleNote)
        #expect(Self.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(1)]),
                                   OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(0)])])
        PadsTests.press(rig, Self.cycleNote)
        #expect(Self.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/SetCueLoop", [.int(1)])])
        PadsTests.press(rig, Self.cycleNote)
        #expect(Self.pad1(rig) == [])
        PadsTests.press(rig, Self.cycleNote)
        #expect(Self.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(1)]),
                                   OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])
    }

    @Test("Cycling with a pad held lets the held hot cue go first, as the four buttons do")
    func releasesHeldPad() throws {
        let rig = try Self.started(Self.cycling)
        PadsTests.down(rig, PadsTests.pad1)
        rig.osc.sent.removeAll()
        PadsTests.press(rig, Self.cycleNote)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])
    }

    @Test("The mode LEDs follow the cycle: Roll lights note 28 full, Hot Cue's 27 drops to dim")
    func modeLEDsFollow() throws {
        let rig = try Self.started(Self.cycling)
        #expect(rig.leds[27] == 127)
        PadsTests.press(rig, Self.cycleNote)
        #expect(rig.leds[28] == 127)
        #expect(rig.leds[27] == 1)
    }

    @Test("The cycle button's own LED shows each mode's velocity from the profile: 127, 64, 32, 1")
    func cycleLED() throws {
        let rig = try Self.started(Self.cyclingLit)
        var seen: [UInt8?] = [rig.leds[120]]
        for _ in 1...3 {
            PadsTests.press(rig, Self.cycleNote)
            seen.append(rig.leds[120])
        }
        #expect(seen == [127, 64, 32, 1])
    }

    @Test("With no velocities, DeckBridge leaves the cycle button's LED alone")
    func cycleLEDLeftAlone() throws {
        let rig = try Self.started(Self.cycling)
        PadsTests.press(rig, Self.cycleNote)
        #expect(rig.leds[120] == nil)
    }
}

/// The LC6000 is unchanged by #198: its four buttons pick the mode, and a mode_cycle note does nothing under "buttons".
@Suite("Pad mode buttons unchanged")
struct PadModeButtonsUnchangedTests {
    @Test("With the four buttons, a mapped mode_cycle note neither changes the mode nor lights")
    func cycleIgnored() throws {
        let rig = try PadModeCycleCoordinatorTests.started(
            #"{ "notes": { "mode_cycle": 120 }, "pads": { "mode_cycle_velocities": { "hotcue": 127, "roll": 64, "loop": 32, "slicer": 1 } } }"#)
        PadsTests.press(rig, PadModeCycleCoordinatorTests.cycleNote)
        #expect(PadModeCycleCoordinatorTests.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(1)]),
                                                          OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])
        #expect(rig.leds[120] == nil)
    }

    @Test("The bundled LC6000: Roll's button (28) picks Roll and lights; Loop's (30) picks cue loop")
    func lc6000Buttons() throws {
        let rig = try PadModeCycleCoordinatorTests.started(nil)
        PadsTests.press(rig, PadsTests.modeRoll)
        #expect(rig.leds[28] == 127)
        #expect(PadModeCycleCoordinatorTests.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(1)]),
                                                          OSCMessage("/Syndicate/Deck/1/SlipLoop/ThirtySecond", [.int(0)])])
        PadsTests.press(rig, PadsTests.modeLoop)
        #expect(PadModeCycleCoordinatorTests.pad1(rig) == [OSCMessage("/Syndicate/Deck/1/SetCueLoop", [.int(1)])])
    }
}

/// The import check and decoder (#198), in plain words.
@Suite("Pad mode select in the import check")
struct PadModeSelectImportTests {
    static func importing(_ json: String) throws {
        _ = try ControllerProfile.importing(Data(json.utf8), bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
    }

    @Test("mode_select is buttons or cycle")
    func unknownValue() {
        #expect(throws: MappingError.invalid([#"mapping.pads.mode_select: "cycling" isn't one of buttons, cycle"#])) {
            try Self.importing(#"{"mapping": {"pads": {"mode_select": "cycling"}}}"#)
        }
    }

    @Test("mode_select is text")
    func wrongType() {
        #expect(throws: MappingError.invalid([#"mapping.pads.mode_select: expected text, got 2"#])) {
            try Self.importing(#"{"mapping": {"pads": {"mode_select": 2}}}"#)
        }
    }

    @Test("Each cycle velocity is a MIDI velocity, 0-127")
    func velocityRange() {
        #expect(throws: MappingError.invalid([#"mapping.pads.mode_cycle_velocities.roll: 200 is out of range, expected 0-127"#])) {
            try Self.importing(#"""
                {"mapping": {"notes": {"mode_cycle": 120},
                 "pads": {"mode_select": "cycle", "mode_cycle_velocities": {"hotcue": 127, "roll": 200, "loop": 32, "slicer": 1}}}}
                """#)
        }
    }

    @Test("A cycling profile needs its mode_cycle button")
    func cycleNeedsButton() {
        #expect(throws: MappingError.invalid(["pads: mode_select is cycle, but notes has no mode_cycle button"])) {
            try Self.importing(#"{"mapping": {"pads": {"mode_select": "cycle"}}}"#)
        }
    }

    @Test("A good cycling import works")
    func goodImport() throws {
        try Self.importing(#"{"mapping": {"notes": {"mode_cycle": 120}, "pads": {"mode_select": "cycle"}}}"#)
    }
}
