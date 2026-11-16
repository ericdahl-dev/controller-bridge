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
}
