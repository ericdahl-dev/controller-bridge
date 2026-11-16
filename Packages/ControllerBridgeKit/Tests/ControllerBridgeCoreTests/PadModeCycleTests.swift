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
