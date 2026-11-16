// Which of Syndicate's OSC FEEDBACK subscriptions are on, judged from its answer to a Resend (#150).

/// A Syndicate OSC FEEDBACK subscription, the one list the setup guide shows and the check judges (#211), in the
/// guide's order.
public enum Subscription: String, CaseIterable, Equatable, Sendable {
    case playing, playPending, loaded, progress, tempoSlider, cues, sync, loop

    /// As Syndicate's OSC FEEDBACK screen names it.
    public var syndicateName: String {
        switch self {
        case .playing: "Playing"
        case .playPending: "PlayPending"
        case .loaded: "Loaded and TrackInfo"
        case .progress: "Position/Progress"
        case .tempoSlider: "TempoSlider/TempoSliderEnabled"
        case .cues: "Cues"
        case .sync: "BPM/Sync"
        case .loop: "Loop"
        }
    }

    /// What goes wrong without it, to follow "<name> is off: ".
    public var breaks: String {
        switch self {
        case .playing: "the Play LED doesn't follow the deck"
        case .playPending: "Play won't blink while a quantized start waits"
        case .loaded: "the ring and Cue LED don't show a loaded track, and the jog can't seek by track length"
        case .progress: "the jog seeks from the wrong place while paused"
        case .tempoSlider: "the pitch fader can jump"
        case .cues: "hot cue pads stay dark"
        case .sync: "the Sync LED doesn't follow the deck"
        case .loop: "the loop LEDs don't follow the deck"
        }
    }

    /// The deck values it sends, the last part of each address, lowercased. Any one of them proves it's on: a load
    /// sends TempoSlider without TempoSliderEnabled, and a real Resend sends Position, never Progress (#211 capture).
    public var values: [String] {
        switch self {
        case .playing: ["playing"]
        case .playPending: ["playpending"]
        case .loaded: ["loaded", "trackinfo"]
        case .progress: ["position", "progress"]
        case .tempoSlider: ["temposlider", "temposliderenabled"]
        case .cues: ["cues"]
        case .sync: ["sync", "bpm"]
        case .loop: ["loop"]
        }
    }
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
        // With Loaded and TrackInfo on, every deck sends Loaded, an empty one 0 (#211 capture). Deck values without it
        // mean that subscription is off, and then no deck can be judged loaded.
        let anyLoadedValue = values.values.contains { $0.contains("loaded") || $0.contains("trackinfo") }
        if !values.isEmpty, !anyLoadedValue {
            missing = [.loaded]
            return
        }
        missing = Subscription.allCases.filter { subscription in
            // Loaded is what marks a deck loaded, judged above.
            guard subscription != .loaded else { return false }
            return loaded.contains { deck in !subscription.values.contains { (values[deck] ?? []).contains($0) } }
        }
    }

    /// A deck or header value: some deck subscriptions are on.
    static func provesSubscriptions(_ address: String) -> Bool {
        let path = address.lowercased()
        return path.contains("/deck/") || path.contains("/header/")
    }
}
