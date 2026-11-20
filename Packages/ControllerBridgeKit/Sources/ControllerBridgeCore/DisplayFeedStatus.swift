// The display feed's status line in Settings (#618): what the feed is doing, from its setting and its destination, so
// a feed that can't send never fails silently.

public enum DisplayFeedStatus: Equatable, Sendable {
    case off
    /// On, with no destination open yet: the address is being looked up or opened.
    case connecting(String)
    /// The destination is open and sends go out. UDP says nothing about a panel that is off or deaf, so this is
    /// "sending", never "connected" or "received" (#618).
    case sending(String)
    /// On, but the address can't be used: the reason.
    case notSending(String)

    /// `destination` is the feed's own, never the Syndicate link's.
    public init(_ settings: DisplayFeedSettings, _ destination: OSCDestination) {
        let address = "\(settings.host.trimmingCharacters(in: .whitespaces)):\(settings.port)"
        if !settings.enabled {
            self = .off
        } else if let problem = destination.lastError {
            // Before "sending": a new address that failed leaves the old one open, which isn't the one asked for.
            self = .notSending(problem)
        } else if destination.isReady {
            self = .sending(address)
        } else {
            self = .connecting(address)
        }
    }

    /// The line Settings shows.
    public var text: String {
        switch self {
        case .off: "Off"
        case .connecting(let address): "Connecting to \(address)…"
        case .sending(let address): "Sending to \(address)"
        case .notSending(let reason): "Not sending: \(reason)"
        }
    }
}
