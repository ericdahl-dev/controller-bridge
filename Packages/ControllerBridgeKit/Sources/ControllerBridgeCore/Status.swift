/// What the menu shows: each controller's deck and whether it is connected, and the last thing that happened to it.
public struct CoordinatorStatus: Equatable, Sendable {
    public var controllers: [ControllerStatus]
    /// Every connected MIDI source and the controller profile it matched, if any.
    public var devices: [DeviceStatus]
    /// Whether Syndicate's feedback is arriving (#21).
    public var feedback: FeedbackState
    /// The last time feedback stopped, for the menu.
    public var lastDropout: String?
    /// An LED sweep (#26) is running.
    public var sweeping = false
    /// The built-in demo controller (#64) is running instead of the real one.
    public var demo = false

    public init(
        controllers: [ControllerStatus], devices: [DeviceStatus] = [], feedback: FeedbackState = .waiting,
        lastDropout: String? = nil
    ) {
        self.controllers = controllers
        self.devices = devices
        self.feedback = feedback
        self.lastDropout = lastDropout
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
    /// The deck is Syndicate's tempo master: the same rule as the Master LED (#53).
    public var master: Bool
    /// The controller's LED output is open, so the LED sweep can run (#70).
    public var outputOpen: Bool
    /// The profile's name from the last connection, kept after a disconnect so the panel can still name it (#91).
    public var lastProfile: String?
    /// Why it last disconnected, if it has (#91).
    public var lastDisconnect: DisconnectReason?

    public init(
        deck: Int, connected: Bool, lastEvent: String? = nil, profile: String? = nil, master: Bool = false, outputOpen: Bool = false,
        lastProfile: String? = nil, lastDisconnect: DisconnectReason? = nil
    ) {
        self.lastProfile = lastProfile
        self.lastDisconnect = lastDisconnect
        self.deck = deck
        self.connected = connected
        self.lastEvent = lastEvent
        self.profile = profile
        self.master = master
        self.outputOpen = outputOpen
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

/// Syndicate's feedback, as the bridge sees it.
public enum FeedbackState: Equatable, Sendable {
    /// None has arrived since launch.
    case waiting
    /// Arriving, or quiet but answering when asked.
    case live
    /// Stopped: it didn't answer a resend request. Syndicate's LEDs show idle until it comes back.
    case stale
}

/// Why a controller disconnected (#91): only an unplug is an unplug.
public enum DisconnectReason: Equatable, Sendable {
    /// Its MIDI source went away.
    case unplugged
    /// Sending to its LEDs failed.
    case sendFailed
    /// Reading from it failed.
    case inputFailed
    /// Settings chose other devices for it.
    case deviceChanged
    /// Its controller entry was removed in Settings.
    case removed
    /// The bridge stopped (quit).
    case stopped
}
