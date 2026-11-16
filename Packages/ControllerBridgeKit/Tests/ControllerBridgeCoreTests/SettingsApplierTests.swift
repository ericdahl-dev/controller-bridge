import ControllerBridgeCore
import Testing

/// Applying settings (#136): everything but the host applies and saves at once; only the host waits on the network,
/// and when it opens it lands on the settings as they are then, so nothing reverts anything.
@Suite("Settings applier") @MainActor
struct SettingsApplierTests {
    typealias Store = SettingsTests.MemoryStore

    /// Records what the app was told to change, as (old deck, new deck) pairs.
    final class Effects: @unchecked Sendable {
        var decks: [Int] = []
    }

    static func applier(_ store: Store, effects: Effects, connect: @escaping @Sendable (String, Int) async -> String?) -> SettingsApplier {
        SettingsApplier(settings: SettingsTests.defaults, storage: store, connect: connect) { _, new in
            effects.decks.append(new.controllers[0].deck)
        }
    }

    static func saved(_ store: Store) -> BridgeSettings {
        BridgeSettings.load(from: store, defaults: SettingsTests.defaults)
    }

    @Test("A deck click applies and saves at once, with no connect")
    func deckClickIsImmediate() throws {
        let store = Store(), effects = Effects()
        let applier = Self.applier(store, effects: effects) { _, _ in Issue.record("no connect for a deck click"); return nil }
        var new = applier.settings
        new.controllers[0].deck = 3
        _ = try applier.applyNow(new)
        #expect(effects.decks == [3])
        #expect(Self.saved(store).controllers[0].deck == 3)
    }

    @Test("A bad host with a deck change: the deck applies and saves, the host error is reported, the old host stays saved")
    func badHostKeepsDeck() async throws {
        let store = Store(), effects = Effects()
        let applier = Self.applier(store, effects: effects) { host, _ in "Can't find \(host) on the network" }
        var new = applier.settings
        new.controllers[0].deck = 3
        new.syndicateHost = "nowhere.local"
        await #expect(throws: SettingsError.fields([SettingsProblem(field: .host, message: "Can't find nowhere.local on the network")])) {
            try await applier.apply(new, senderReady: true)
        }
        #expect(effects.decks == [3])
        #expect(Self.saved(store).controllers[0].deck == 3)
        #expect(Self.saved(store).syndicateHost == "127.0.0.1")
    }

    @Test("A deck click while a host change resolves: both stay, in the settings and saved")
    func deckDuringHostChange() async throws {
        let store = Store(), effects = Effects()
        let gate = AsyncStream<Void>.makeStream()
        let applier = Self.applier(store, effects: effects) { _, _ in
            for await _ in gate.stream { break }
            return nil
        }
        var hostChange = applier.settings
        hostChange.syndicateHost = "studio.local"
        async let applied: Void = applier.apply(hostChange, senderReady: true)
        try await Task.sleep(for: .milliseconds(50))
        var deckClick = applier.settings
        deckClick.controllers[0].deck = 4
        _ = try applier.applyNow(deckClick)
        gate.continuation.yield()
        try await applied
        #expect(applier.settings.controllers[0].deck == 4)
        #expect(applier.settings.syndicateHost == "studio.local")
        #expect(Self.saved(store) == applier.settings)
    }

    @Test("Two host changes in flight: the later request wins, even if the earlier one opens last")
    func laterHostWins() async throws {
        let store = Store(), effects = Effects()
        let gate = AsyncStream<Void>.makeStream()
        let applier = Self.applier(store, effects: effects) { host, _ in
            if host == "slow.local" { for await _ in gate.stream { break } }
            return nil
        }
        var first = applier.settings
        first.syndicateHost = "slow.local"
        async let slow: Void = applier.apply(first, senderReady: true)
        try await Task.sleep(for: .milliseconds(50))
        var second = applier.settings
        second.syndicateHost = "192.168.1.20"
        try await applier.apply(second, senderReady: true)
        gate.continuation.yield()
        try await slow
        #expect(applier.settings.syndicateHost == "192.168.1.20")
        #expect(Self.saved(store).syndicateHost == "192.168.1.20")
    }
}
