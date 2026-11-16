import Foundation
import Synchronization

/// One open socket to Syndicate: it sends a datagram, and throws when the send fails (EHOSTUNREACH and the like).
public protocol DatagramSink: Sendable {
    func send(_ bytes: [UInt8]) throws
}

/// Turns a host name into an IPv4 address, off the caller's thread: a `.local` lookup can take seconds.
public protocol HostResolver: Sendable {
    func resolve(_ host: String) async throws -> String
}

/// Where the bridge's OSC goes (#84, #109): Syndicate's host by IPv4 address or by name. `send` never waits: until a
/// destination is open, messages are dropped. A new destination opens before the old one is let go, so a bad host
/// or a name that can't be found leaves the old one working.
public final class OSCDestination: OSCSender {
    public typealias Open = @Sendable (_ ipv4: String, _ port: Int) throws -> any DatagramSink

    private struct State {
        var sink: (any DatagramSink)?
        var onReady: (@Sendable () -> Void)?
        var lastError: String?
        var address = ""
        var onSendFailure: (@Sendable () -> Void)?
        var lastFailureReport: Double?
    }

    private let resolver: any HostResolver
    private let open: Open
    private let clock: any Clock
    private let state = Mutex(State())
    private let lookupTimeout: Duration

    /// `lookupTimeout`: a hung mDNS lookup gives up after this, with the same "Can't find" as a failed one.
    public init(resolver: any HostResolver, open: @escaping Open, clock: any Clock, lookupTimeout: Duration = .seconds(5)) {
        self.resolver = resolver
        self.open = open
        self.clock = clock
        self.lookupTimeout = lookupTimeout
    }

    /// Called when sends start failing (such as EHOSTUNREACH after the host's address changed), at most once a second.
    /// The app re-resolves the name then.
    public var onSendFailure: (@Sendable () -> Void)? {
        get { state.withLock { $0.onSendFailure } }
        set { state.withLock { $0.onSendFailure = newValue } }
    }

    /// A destination is open: sends go out.
    public var isReady: Bool { state.withLock { $0.sink != nil } }

    /// Why the last connect, or the last send, failed; nil once a destination opens and sends work.
    public var lastError: String? { state.withLock { $0.lastError } }

    /// Called each time a destination opens, so the app can ask Syndicate to resend its state: anything sent while
    /// there was no destination was dropped.
    public var onReady: (@Sendable () -> Void)? {
        get { state.withLock { $0.onReady } }
        set { state.withLock { $0.onReady = newValue } }
    }

    /// Points the destination at `host`, an IPv4 address or a name resolved off the caller. Returns why it couldn't,
    /// with the old destination still in use; nil when the new one is open.
    public func connect(host: String, port: Int) async -> String? {
        let address: String
        if BridgeSettings.isIPv4(host) {
            address = host
        } else {
            guard let resolved = await lookUp(host) else { return failed("Can't find \(host) on the network") }
            address = resolved
        }
        do {
            let sink = try open(address, port)
            let ready = state.withLock { state -> (@Sendable () -> Void)? in
                state.sink = sink
                state.address = "\(address):\(port)"
                state.lastError = nil
                return state.onReady
            }
            ready?()
            return nil
        } catch {
            return failed("Couldn't send OSC to \(address):\(port)")
        }
    }

    /// Records why a connect failed and returns it; the old destination, if any, stays.
    private func failed(_ problem: String) -> String {
        state.withLock { $0.lastError = problem }
        return problem
    }

    /// The resolver's answer, or nil if it fails or takes longer than the timeout. The lookup isn't awaited past the
    /// timeout: a hung one is left behind, since a resolver may not stop when cancelled.
    private func lookUp(_ host: String) async -> String? {
        let resolver = self.resolver, timeout = lookupTimeout
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let resumed = Mutex(false)
            let finish: @Sendable (String?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Task { finish(try? await resolver.resolve(host)) }
            Task {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }

    public func send(_ message: OSCMessage) {
        guard let sink = state.withLock({ $0.sink }) else { return }
        do {
            try sink.send(message.encoded())
        } catch {
            let now = clock.now
            let report = state.withLock { state -> (@Sendable () -> Void)? in
                state.lastError = "Couldn't send OSC to \(state.address)"
                if let last = state.lastFailureReport, now - last < 1 { return nil }
                state.lastFailureReport = now
                return state.onSendFailure
            }
            report?()
        }
    }
}
