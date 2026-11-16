import ControllerBridgeCore
import Foundation
import Testing

/// The smoke check pins the app to its own virtual MIDI device by writing these saved settings before launch (#86),
/// so a real controller plugged into the same Mac can't take its place. This keeps the template the script writes in
/// the app's own settings format.
@Suite("Smoke settings")
struct SmokeSettingsTests {
    static func template() throws -> String {
        // Tests/ControllerBridgeCoreTests/ → repo root → scripts/smoke/.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../scripts/smoke/settings-template.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("With the helper's endpoint ids filled in, the template is valid saved settings pinning controller 1 to them")
    func templatePinsTheHelper() throws {
        let json = try Self.template()
            .replacingOccurrences(of: "__INPUT_ID__", with: "-1234567")
            .replacingOccurrences(of: "__OUTPUT_ID__", with: "7654321")
        let settings = try JSONDecoder().decode(BridgeSettings.self, from: Data(json.utf8))
        #expect(settings.controllers == [ControllerSettings(
            deck: 1,
            input: MIDIEndpoint(id: -1_234_567, name: "LC6000 Smoke"),
            output: MIDIEndpoint(id: 7_654_321, name: "LC6000 Smoke")
        )])
        #expect(settings.syndicatePort == 9090)
        #expect(settings.feedbackPort == 9096)
        #expect(settings.problems == [])
    }
}
