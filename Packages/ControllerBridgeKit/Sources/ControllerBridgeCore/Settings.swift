import Foundation

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

extension BridgeSettings {
    /// The user-defaults key the settings are kept under, as JSON.
    public static let storageKey = "settings.v1"

    /// The saved settings, or `defaults` when nothing is saved or what is saved can't be read.
    public static func load(from storage: any SettingsStorage, defaults: BridgeSettings) -> BridgeSettings {
        guard let data = storage.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(BridgeSettings.self, from: data) else { return defaults }
        return settings
    }

    /// Saves the settings, or throws every problem and leaves the saved settings as they were.
    public func save(to storage: any SettingsStorage) throws(SettingsError) {
        let problems = problems
        guard problems.isEmpty else { throw .invalid(problems) }
        // Encoding plain values can't fail.
        guard let data = try? JSONEncoder().encode(self) else { return }
        storage.set(data, forKey: Self.storageKey)
    }

    /// What's wrong, in Syndicate's words, so the DJ can fix it.
    public var problems: [String] {
        var out: [String] = []
        for controller in controllers where !(1...4).contains(controller.deck) {
            out.append("Deck \(controller.deck) is out of range, expected 1-4")
        }
        if syndicateHost.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("The Syndicate host can't be empty")
        }
        let ports = 1...65_535
        if !ports.contains(syndicatePort) { out.append("OSC port \(syndicatePort) is out of range, expected 1-65535") }
        if !ports.contains(feedbackPort) { out.append("Feedback port \(feedbackPort) is out of range, expected 1-65535") }
        if syndicatePort == feedbackPort {
            out.append("The OSC port and the Feedback port can't both be \(syndicatePort)")
        }
        return out
    }
}

/// Settings that can't be saved, with a plain message for each problem.
public enum SettingsError: Error, Equatable {
    case invalid([String])
}

/// Where settings are kept: user defaults in the app.
public protocol SettingsStorage {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

/// One controller: the Syndicate deck it drives and the MIDI devices it uses.
public struct ControllerSettings: Codable, Equatable, Sendable {
    /// 1-4.
    public var deck: Int
    /// The chosen MIDI input and output. Nil is automatic: the first device a controller profile matches.
    public var input: MIDIEndpoint?
    public var output: MIDIEndpoint?
    /// The MIDI channel, 1-16, to tell two controllers on one device apart (#25). Nil is the profile's channel.
    public var channel: Int?

    public init(deck: Int, input: MIDIEndpoint?, output: MIDIEndpoint?, channel: Int? = nil) {
        self.deck = deck
        self.input = input
        self.output = output
        self.channel = channel
    }
}

/// Which network interfaces listen for Syndicate's feedback.
public enum FeedbackListen: String, Codable, Equatable, Sendable {
    /// Loopback only: Syndicate runs on this Mac. The default, with no local-network prompt.
    case thisMac
    /// Every interface, for Syndicate on another Mac. macOS asks for local-network permission.
    case allNetworks

    /// The IPv4 address the feedback listener binds to.
    public var address: String {
        switch self {
        case .thisMac: "127.0.0.1"
        case .allNetworks: "0.0.0.0"
        }
    }
}
