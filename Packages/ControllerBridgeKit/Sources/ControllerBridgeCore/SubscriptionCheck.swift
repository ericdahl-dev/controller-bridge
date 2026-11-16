// Which of Syndicate's OSC FEEDBACK subscriptions are on, judged from its answer to a Resend (#150).

/// Syndicate answers a Resend with every subscribed value, and always ColorPalette. Values for an empty deck aren't
/// sent, so only what arrived counts, never what didn't arrive.
struct SubscriptionCheck: Equatable {
    /// The answer had no deck and no header values (BPM, Metronome, MasterVolume…): subscriptions are off.
    var noDeckData: Bool

    /// Nil for no answer at all: silence says nothing about subscriptions.
    init?(answer addresses: [String]) {
        guard !addresses.isEmpty else { return nil }
        noDeckData = !addresses.contains(where: Self.provesSubscriptions)
    }

    /// A deck or header value: some deck subscriptions are on.
    static func provesSubscriptions(_ address: String) -> Bool {
        let path = address.lowercased()
        return path.contains("/deck/") || path.contains("/header/")
    }
}
