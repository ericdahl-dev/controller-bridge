/// Putting settings into effect (#136). Everything but Syndicate's host and port applies and saves at once, so a
/// deck click never waits on the network. Only a host change awaits its connect, and when it opens it lands on the
/// settings as they are then: a deck picked meanwhile stays, and of two host changes in flight the later one wins.
@MainActor
public final class SettingsApplier {
    public typealias Connect = @Sendable (_ host: String, _ port: Int) async -> String?
    /// What the app does for a change: tell the Coordinator, update the status.
    public typealias Effects = (_ old: BridgeSettings, _ new: BridgeSettings) -> Void

    public private(set) var settings: BridgeSettings
    private let storage: any SettingsStorage
    private let connect: Connect
    private let effects: Effects
    /// Counts host requests, so a connect that finishes after a newer one doesn't save over it.
    private var hostRequest = 0

    public init(settings: BridgeSettings, storage: any SettingsStorage, connect: @escaping Connect, effects: @escaping Effects) {
        self.settings = settings
        self.storage = storage
        self.connect = connect
        self.effects = effects
    }

    /// Checks `new`, then applies and saves everything but its host and port at once. Returns the host and port still
    /// to open, if they changed (or, with `senderReady` false and `retry`, if the sender never opened).
    @discardableResult
    public func applyNow(_ new: BridgeSettings, senderReady: Bool = true, retry: Bool = false) throws(SettingsError) -> BridgeSettings.Connection? {
        let problems = new.problems
        guard problems.isEmpty else { throw .invalid(problems) }
        let old = settings
        let now = BridgeSettings.immediate(new, keeping: old)
        if now != old {
            try now.save(to: storage)
            settings = now
            effects(old, now)
        }
        return BridgeSettings.connection(to: new, from: old, senderReady: senderReady, retry: retry)
    }

    /// Settings' Apply: `applyNow`, then opens a new host. A host that can't be opened throws under the host field;
    /// everything else stays applied.
    public func apply(_ new: BridgeSettings, senderReady: Bool) async throws(SettingsError) {
        guard let target = try applyNow(new, senderReady: senderReady, retry: true) else { return }
        hostRequest += 1
        let request = hostRequest
        if let problem = await connect(target.host, target.port) {
            throw .fields([SettingsProblem(field: .host, message: problem)])
        }
        // A newer host request owns the host now.
        guard request == hostRequest else { return }
        let old = settings
        let connected = old.connected(host: target.host, port: target.port)
        guard connected != old else { return }
        try connected.save(to: storage)
        settings = connected
        effects(old, connected)
    }
}

extension BridgeSettings {
    /// Syndicate's host and port, to open.
    public struct Connection: Equatable, Sendable {
        public var host: String
        public var port: Int

        public init(host: String, port: Int) {
            self.host = host
            self.port = port
        }
    }

    /// What `new` needs opened: its host and port when they changed. With `retry` (Settings' Apply), also when the
    /// sender never opened (#109). A deck, LED, color or device change needs nothing.
    public static func connection(to new: BridgeSettings, from old: BridgeSettings, senderReady: Bool, retry: Bool = true) -> Connection? {
        let changed = new.syndicateHost != old.syndicateHost || new.syndicatePort != old.syndicatePort
        guard changed || (retry && !senderReady) else { return nil }
        return Connection(host: new.syndicateHost, port: new.syndicatePort)
    }

    /// `new`, with `old`'s host and port: the part that applies without the network.
    public static func immediate(_ new: BridgeSettings, keeping old: BridgeSettings) -> BridgeSettings {
        var out = new
        out.syndicateHost = old.syndicateHost
        out.syndicatePort = old.syndicatePort
        return out
    }

    /// These settings with a host and port that just opened.
    public func connected(host: String, port: Int) -> BridgeSettings {
        var out = self
        out.syndicateHost = host
        out.syndicatePort = port
        return out
    }
}
