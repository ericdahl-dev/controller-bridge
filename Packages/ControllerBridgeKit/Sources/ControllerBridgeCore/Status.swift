/// What the menu shows: each controller's deck and whether it is connected, and the last thing that happened to it.
public struct CoordinatorStatus: Equatable, Sendable {
    public var controllers: [ControllerStatus]

    public init(controllers: [ControllerStatus]) { self.controllers = controllers }
}

public struct ControllerStatus: Equatable, Sendable {
    /// The Syndicate deck this controller drives, 1-4.
    public var deck: Int
    public var connected: Bool
    /// The last disconnect or reconnect, for the menu.
    public var lastEvent: String?

    public init(deck: Int, connected: Bool, lastEvent: String? = nil) {
        self.deck = deck
        self.connected = connected
        self.lastEvent = lastEvent
    }
}
