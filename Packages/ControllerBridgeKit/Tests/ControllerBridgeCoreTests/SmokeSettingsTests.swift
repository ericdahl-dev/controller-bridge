import ControllerBridgeCore
import Foundation
import Testing

/// The smoke check writes these saved settings before launch: one controller on automatic devices, as on a real unit,
/// so the app must pick the controls ports over the WD ones itself (#143). This keeps the template in the app's own
/// settings format.
@Suite("Smoke settings")
struct SmokeSettingsTests {
    static func template() throws -> String {
        // Tests/ControllerBridgeCoreTests/ → repo root → scripts/smoke/.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../scripts/smoke/settings-template.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("The template is valid saved settings: controller 1 on deck 1, automatic devices, following layers (#143)")
    func templateIsAutomatic() throws {
        let settings = try JSONDecoder().decode(BridgeSettings.self, from: Data(Self.template().utf8))
        #expect(settings.controllers == [ControllerSettings(deck: 1, input: nil, output: nil)])
        #expect(settings.controllers[0].followLayers ?? true)
        #expect(settings.syndicatePort == 9090)
        #expect(settings.feedbackPort == 9096)
        #expect(settings.problems == [])
    }

    @Test("With a real LC6000 attached, the pinned template pins controller 1 to the helper's controls ports (#86)")
    func pinnedTemplatePinsTheHelper() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../scripts/smoke/settings-pinned-template.json")
        let json = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "__INPUT_ID__", with: "-1234567")
            .replacingOccurrences(of: "__OUTPUT_ID__", with: "7654321")
        let settings = try JSONDecoder().decode(BridgeSettings.self, from: Data(json.utf8))
        #expect(settings.controllers == [ControllerSettings(
            deck: 1,
            input: MIDIEndpoint(id: -1_234_567, name: "Smoke LC6000 PRIME Controller"),
            output: MIDIEndpoint(id: 7_654_321, name: "Smoke LC6000 PRIME Controller")
        )])
        #expect(settings.problems == [])
    }
}
