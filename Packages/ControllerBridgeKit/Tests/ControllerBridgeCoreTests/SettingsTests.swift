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

    /// User defaults stand-in.
    final class MemoryStore: SettingsStorage, @unchecked Sendable {
        var values: [String: Data] = [:]
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ data: Data, forKey key: String) { values[key] = data }
    }

    static let defaults = BridgeSettings(
        controllers: [ControllerSettings(deck: 1, input: nil, output: nil)],
        syndicateHost: "127.0.0.1", syndicatePort: 9090, feedbackPort: 9096, feedbackListen: .thisMac, ledsEnabled: true
    )

    @Test("Saved settings load back as saved")
    func roundTrip() throws {
        let store = MemoryStore()
        var changed = Self.defaults
        changed.controllers[0] = ControllerSettings(
            deck: 3, input: MIDIEndpoint(id: 1001, name: "DENON LC6000 PRIME"), output: MIDIEndpoint(id: 2001, name: "DENON LC6000 PRIME")
        )
        changed.syndicateHost = "192.168.1.20"
        changed.feedbackListen = .allNetworks
        changed.ledsEnabled = false
        changed.save(to: store)
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == changed)
    }

    @Test("Nothing saved, or saved data that can't be read, loads the defaults")
    func missingOrCorruptLoadsDefaults() {
        let store = MemoryStore()
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == Self.defaults)
        store.values[BridgeSettings.storageKey] = Data("not json".utf8)
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == Self.defaults)
    }
}
