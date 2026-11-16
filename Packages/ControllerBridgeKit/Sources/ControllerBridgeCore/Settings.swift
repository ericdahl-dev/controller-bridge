/// What the DJ sets in Settings (#19): the controllers, the OSC connection to Syndicate and the LEDs. Kept in user
/// defaults by the app.
public struct BridgeSettings: Codable, Equatable, Sendable {
    /// One entry per controller. One for now; multiple controllers (#25) add entries.
    public var controllers: [ControllerSettings]
    /// Syndicate's computer, and its OSC listen port.
    public var syndicateHost: String
    public var syndicatePort: Int
    /// Where Syndicate sends its OSC feedback.
    public var feedbackPort: Int
    public var feedbackListen: FeedbackListen
    public var ledsEnabled: Bool

    public init(
        controllers: [ControllerSettings], syndicateHost: String, syndicatePort: Int, feedbackPort: Int,
        feedbackListen: FeedbackListen, ledsEnabled: Bool
    ) {
        self.controllers = controllers
        self.syndicateHost = syndicateHost
        self.syndicatePort = syndicatePort
        self.feedbackPort = feedbackPort
        self.feedbackListen = feedbackListen
        self.ledsEnabled = ledsEnabled
    }

    /// The settings before the DJ changes anything, taken from a controller profile's mapping.
    public static func defaults(from mapping: Mapping) -> BridgeSettings {
        BridgeSettings(
            controllers: [ControllerSettings(deck: mapping.deck.number, input: nil, output: nil)],
            syndicateHost: mapping.osc.host,
            syndicatePort: mapping.osc.port,
            feedbackPort: mapping.osc.feedbackPort,
            feedbackListen: .thisMac,
            ledsEnabled: true
        )
    }
}

/// One controller: the Syndicate deck it drives and the MIDI devices it uses.
public struct ControllerSettings: Codable, Equatable, Sendable {
    /// 1-4.
    public var deck: Int
    /// The chosen MIDI input and output. Nil is automatic: the first device a controller profile matches.
    public var input: MIDIEndpoint?
    public var output: MIDIEndpoint?

    public init(deck: Int, input: MIDIEndpoint?, output: MIDIEndpoint?) {
        self.deck = deck
        self.input = input
        self.output = output
    }
}

/// Which network interfaces listen for Syndicate's feedback.
public enum FeedbackListen: String, Codable, Equatable, Sendable {
    /// Loopback only: Syndicate runs on this Mac. The default, with no local-network prompt.
    case thisMac
    /// Every interface, for Syndicate on another Mac. macOS asks for local-network permission.
    case allNetworks
}
