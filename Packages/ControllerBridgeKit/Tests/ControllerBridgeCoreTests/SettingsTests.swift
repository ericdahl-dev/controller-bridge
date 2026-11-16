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
        try changed.save(to: store)
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == changed)
    }

    @Test("Nothing saved, or saved data that can't be read, loads the defaults")
    func missingOrCorruptLoadsDefaults() {
        let store = MemoryStore()
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == Self.defaults)
        store.values[BridgeSettings.storageKey] = Data("not json".utf8)
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == Self.defaults)
    }

    @Test("This Mac only listens on 127.0.0.1; All networks listens on 0.0.0.0")
    func listenAddress() {
        #expect(FeedbackListen.thisMac.address == "127.0.0.1")
        #expect(FeedbackListen.allNetworks.address == "0.0.0.0")
    }

    @Test("Bad settings are refused with every problem in plain words, and the saved settings stay as they were")
    func badSettingsRefused() throws {
        let store = MemoryStore()
        try Self.defaults.save(to: store)
        var bad = Self.defaults
        bad.controllers[0].deck = 5
        bad.syndicateHost = "  "
        bad.syndicatePort = 0
        bad.feedbackPort = 70_000
        #expect(throws: SettingsError.invalid([
            "Deck 5 is out of range, expected 1-4",
            "The Syndicate host can't be empty",
            "OSC port 0 is out of range, expected 1-65535",
            "Feedback port 70000 is out of range, expected 1-65535",
        ])) { try bad.save(to: store) }
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == Self.defaults)
    }

    @Test("The OSC port and the Feedback port can't be the same")
    func portsMustDiffer() {
        var bad = Self.defaults
        bad.feedbackPort = 9090
        #expect(throws: SettingsError.invalid(["The OSC port and the Feedback port can't both be 9090"])) {
            try bad.save(to: MemoryStore())
        }
    }

    static let lc6000 = MIDIEndpoint(id: 1001, name: "DENON LC6000 PRIME")

    @Test("Two controllers on the same device and channel are refused; a channel outside 1-16 is too")
    func sameDeviceAndChannelRefused() {
        var bad = Self.defaults
        bad.controllers = [
            ControllerSettings(deck: 1, input: Self.lc6000, output: nil, channel: 1),
            ControllerSettings(deck: 2, input: Self.lc6000, output: nil, channel: 1),
            ControllerSettings(deck: 3, input: nil, output: nil, channel: 17),
        ]
        #expect(throws: SettingsError.invalid([
            "Controller 3: channel 17 is out of range, expected 1-16",
            "Controllers 1 and 2 both use DENON LC6000 PRIME on channel 1",
        ])) { try bad.save(to: MemoryStore()) }
    }

    @Test("Two controllers on one deck is allowed, with a warning that doesn't stop the save")
    func sameDeckWarns() throws {
        let store = MemoryStore()
        var settings = Self.defaults
        settings.controllers = [
            ControllerSettings(deck: 1, input: Self.lc6000, output: nil, channel: 1),
            ControllerSettings(deck: 1, input: Self.lc6000, output: nil, channel: 2),
        ]
        #expect(settings.warnings == ["Controllers 1 and 2 both drive Deck 1"])
        try settings.save(to: store)
        #expect(BridgeSettings.load(from: store, defaults: Self.defaults) == settings)
    }
}
