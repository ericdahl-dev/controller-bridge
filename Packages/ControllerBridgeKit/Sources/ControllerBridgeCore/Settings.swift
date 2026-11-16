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

    /// Allowed, but worth a second look before playing.
    public var warnings: [String] {
        pairs.filter { $0.settings.deck == $1.settings.deck }.map { first, second in
            "Controllers \(first.number) and \(second.number) both drive Deck \(first.settings.deck)"
        }
    }

    /// Every pair of controller entries, numbered from 1 as Settings shows them.
    private var pairs: [(ControllerEntry, ControllerEntry)] {
        let entries = zip(1..., controllers).map { ControllerEntry(number: $0, settings: $1) }
        return entries.indices.flatMap { i in entries.indices.filter { $0 > i }.map { (entries[i], entries[$0]) } }
    }

    private struct ControllerEntry {
        var number: Int
        var settings: ControllerSettings
    }

    /// What's wrong, in Syndicate's words, so the DJ can fix it.
    /// What's wrong, in Syndicate's words, so the DJ can fix it.
    public var problems: [String] { fieldProblems.map(\.message) }

    /// The same problems, each with the field it belongs to, so Settings can show it there (#68).
    public var fieldProblems: [SettingsProblem] {
        var out: [SettingsProblem] = []
        for (index, controller) in controllers.enumerated() where !(1...4).contains(controller.deck) {
            out.append(SettingsProblem(field: .deck(controller: index), message: "Deck \(controller.deck) is out of range, expected 1-4"))
        }
        for (index, controller) in controllers.enumerated() {
            if let channel = controller.channel, !(1...16).contains(channel) {
                out.append(SettingsProblem(
                    field: .channel(controller: index), message: "Controller \(index + 1): channel \(channel) is out of range, expected 1-16"
                ))
            }
        }
        for (first, second) in pairs where first.settings.input != nil && first.settings.input?.id == second.settings.input?.id
            && first.settings.channel == second.settings.channel {
            let channel = first.settings.channel.map { "channel \($0)" } ?? "the same channel"
            out.append(SettingsProblem(
                field: .device(controller: second.number - 1),
                message: "Controllers \(first.number) and \(second.number) both use \(first.settings.input!.name) on \(channel)"
            ))
        }
        let host = syndicateHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            out.append(SettingsProblem(field: .host, message: "The Syndicate host can't be empty"))
        } else if !Self.isIPv4(host) {
            // The OSC sender takes an IPv4 address only, for now (#62).
            out.append(SettingsProblem(
                field: .host, message: "\(host) isn't an IP address. Use the Mac's IP address, like 192.168.1.20 (System Settings › Network)."
            ))
        }
        let ports = 1...65_535
        if !ports.contains(syndicatePort) {
            out.append(SettingsProblem(field: .oscPort, message: "OSC port \(syndicatePort) is out of range, expected 1-65535"))
        }
        if !ports.contains(feedbackPort) {
            out.append(SettingsProblem(field: .feedbackPort, message: "Feedback port \(feedbackPort) is out of range, expected 1-65535"))
        }
        if syndicatePort == feedbackPort {
            out.append(SettingsProblem(field: .feedbackPort, message: "The OSC port and the Feedback port can't both be \(syndicatePort)"))
        }
        return out
    }

    /// Four dot-separated whole numbers, 0-255 each.
    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
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

/// A settings problem and the field it belongs to.
public struct SettingsProblem: Equatable, Sendable {
    public var field: SettingsField
    public var message: String

    public init(field: SettingsField, message: String) {
        self.field = field
        self.message = message
    }
}

/// Where in Settings a problem shows. Controllers are counted from 0.
public enum SettingsField: Hashable, Sendable {
    case deck(controller: Int)
    case channel(controller: Int)
    case device(controller: Int)
    case host
    case oscPort
    case feedbackPort
}
