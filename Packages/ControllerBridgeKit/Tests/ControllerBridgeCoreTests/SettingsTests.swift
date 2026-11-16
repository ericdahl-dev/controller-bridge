import Foundation
import ControllerBridgeCore
import Testing

/// The app's settings: a list of controller entries plus the shared OSC settings, kept in user defaults.
@Suite("Settings")
struct SettingsTests {
    @Test("Defaults come from the LC6000 profile: one controller on deck 1 with no device chosen, Syndicate on loopback")
    func defaults() throws {
        let settings = BridgeSettings.defaults(from: try Mapping.bundledDefault())
        #expect(settings == BridgeSettings(
            controllers: [ControllerSettings(deck: 1, input: nil, output: nil)],
            syndicateHost: "127.0.0.1",
            syndicatePort: 9090,
            feedbackPort: 9096,
            feedbackListen: .thisMac,
            ledsEnabled: true
        ))
    }
}
