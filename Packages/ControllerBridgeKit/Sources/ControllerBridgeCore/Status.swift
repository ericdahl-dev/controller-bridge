/// What the menu shows: each controller's deck and whether it is connected, and the last thing that happened to it.
public struct CoordinatorStatus: Equatable, Sendable {
    public var controllers: [ControllerStatus]
    /// Every connected MIDI source and the controller profile it matched, if any.
    public var devices: [DeviceStatus]

    public init(controllers: [ControllerStatus], devices: [DeviceStatus] = []) {
        self.controllers = controllers
        self.devices = devices
    }
}

public struct ControllerStatus: Equatable, Sendable {
    /// The Syndicate deck this controller drives, 1-4.
    public var deck: Int
    public var connected: Bool
    /// The last disconnect or reconnect, for the menu.
    public var lastEvent: String?
    /// The name of the controller profile in use, while connected.
    public var profile: String?

    public init(deck: Int, connected: Bool, lastEvent: String? = nil, profile: String? = nil) {
        self.deck = deck
        self.connected = connected
        self.lastEvent = lastEvent
        self.profile = profile
    }
}

/// A MIDI source, and the controller profile its name matched.
public struct DeviceStatus: Equatable, Sendable {
    public var name: String
    /// The matched profile's name, or nil if none matched.
    public var profile: String?
    /// A plain message for the menu, such as why the device isn't bridged.
    public var note: String?

    public init(name: String, profile: String?, note: String?) {
        self.name = name
        self.profile = profile
        self.note = note
    }
}
