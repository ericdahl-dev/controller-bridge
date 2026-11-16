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
