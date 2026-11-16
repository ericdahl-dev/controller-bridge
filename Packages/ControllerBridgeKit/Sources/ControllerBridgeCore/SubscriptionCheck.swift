// Which of Syndicate's OSC FEEDBACK subscriptions are on, judged from its answer to a Resend (#150).

/// A Syndicate OSC FEEDBACK subscription that the controller's LEDs need.
public enum Subscription: String, CaseIterable, Equatable, Sendable {
    /// Each is named for the deck value it sends, the last part of its address.
    case playing, cues, sync, loop
}

/// Syndicate answers a Resend with every subscribed value, and always ColorPalette. Values for an empty deck aren't
/// sent, so only what arrived counts: missing values are judged only on a deck that reported Loaded 1.
struct SubscriptionCheck: Equatable {
    /// The answer had no deck and no header values (BPM, Metronome, MasterVolume…): subscriptions are off.
    var noDeckData: Bool
    /// The LED subscriptions a loaded deck lacked.
    var missing: [Subscription]

    /// Nil for no answer at all: silence says nothing about subscriptions.
    init?(answer messages: [OSCMessage]) {
        guard !messages.isEmpty else { return nil }
        noDeckData = !messages.contains { Self.provesSubscriptions($0.address) }
        // Each deck's values, by deck number: the last two parts of /Syndicate/Deck/<n>/<Value>.
        var values: [String: Set<String>] = [:]
        var loaded: Set<String> = []
        for message in messages {
            let parts = message.address.lowercased().split(separator: "/")
            guard parts.count >= 3, parts[parts.count - 3] == "deck" else { continue }
            let deck = String(parts[parts.count - 2]), value = String(parts[parts.count - 1])
            values[deck, default: []].insert(value)
            if value == "loaded", message.arguments.first?.wholeNumber == 1 { loaded.insert(deck) }
        }
        missing = Subscription.allCases.filter { subscription in
            loaded.contains { !(values[$0] ?? []).contains(subscription.rawValue) }
        }
    }

    /// A deck or header value: some deck subscriptions are on.
    static func provesSubscriptions(_ address: String) -> Bool {
        let path = address.lowercased()
        return path.contains("/deck/") || path.contains("/header/")
    }
}
