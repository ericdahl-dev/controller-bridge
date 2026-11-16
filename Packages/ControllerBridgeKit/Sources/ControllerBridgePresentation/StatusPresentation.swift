/// What the bridge knows about itself, as the menu needs it. The app fills this from the Coordinator's status and the
/// feedback listener; it has no CoreMIDI or SwiftUI types, so the wording can be tested here.
public struct BridgeState: Equatable, Sendable {
    public enum Controller: Equatable, Sendable {
        case connected(profile: String)
        case notConnected
        /// A MIDI device is there, but no controller profile matches it (#43).
        case noProfile(device: String)
    }

    public enum Feedback: Equatable, Sendable {
        case starting
        case live(port: Int)
        /// Listening, but Syndicate hasn't answered since launch (#21).
        case waiting(port: Int)
        /// Listening, but Syndicate stopped answering (#21).
        case stopped(port: Int)
        /// Another app holds the port, so no feedback arrives.
        case portInUse(port: Int)
        /// Any other listener failure. The reason goes in the diagnostics (#26), not the status line.
        case failed
    }

    public var controller: Controller
    public var feedback: Feedback
    public var deck: Int
    /// The bridge couldn't start at all; the reason goes in the panel and the diagnostics (#26).
    public var stopped: Bool
    /// The last time Syndicate's feedback stopped (#21), if it has.
    public var lastDropout: String?

    public init(controller: Controller, feedback: Feedback, deck: Int, stopped: Bool = false, lastDropout: String? = nil) {
        self.controller = controller
        self.feedback = feedback
        self.deck = deck
        self.stopped = stopped
        self.lastDropout = lastDropout
    }
}

/// One status light: a dot in `tone`'s color, a label, and a word. The word carries the meaning on its own.
public struct StatusLight: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case live
        /// Nothing wrong, nothing happening: gray.
        case idle
        /// Needs a look, like Syndicate's orange: not broken.
        case attention
        /// Something is broken and the DJ must act: muted red.
        case error
    }

    public var label: String
    public var word: String
    public var tone: Tone

    public init(label: String, word: String, tone: Tone) {
        self.label = label
        self.word = word
        self.tone = tone
    }

    /// A MIDI source that no controller profile matches (#43): listed, not bridged.
    public init(unmatchedDevice name: String) {
        self.init(label: name, word: "NO PROFILE", tone: .attention)
    }
}

/// The menu-bar icon's state dot.
public enum IconState: Equatable, Sendable {
    case ok
    case attention
    case error
}

/// The menu's lights, its Syndicate-style status line and the icon state, in Syndicate's vocabulary.
public struct StatusPresentation: Equatable, Sendable {
    public var lights: [StatusLight]
    public var line: String
    public var icon: IconState
    /// "LAST DROPOUT: …" for the panel, once Syndicate's feedback has stopped at least once (#21).
    public var lastDropout: String?

    public init(_ state: BridgeState) {
        let controller: StatusLight = switch state.controller {
        case .connected(let profile): StatusLight(label: profile, word: "CONNECTED", tone: .live)
        case .notConnected: StatusLight(label: "CONTROLLER", word: "NOT CONNECTED", tone: .idle)
        case .noProfile(let device): StatusLight(label: device, word: "NO PROFILE", tone: .attention)
        }
        let feedback: StatusLight = switch state.feedback {
        case .starting: StatusLight(label: "FEEDBACK", word: "STARTING", tone: .idle)
        case .live: StatusLight(label: "FEEDBACK", word: "LIVE", tone: .live)
        case .waiting: StatusLight(label: "FEEDBACK", word: "WAITING", tone: .idle)
        case .stopped: StatusLight(label: "FEEDBACK", word: "DROPPED", tone: .attention)
        case .portInUse(let port): StatusLight(label: "FEEDBACK", word: "PORT \(port) IN USE", tone: .error)
        case .failed: StatusLight(label: "FEEDBACK", word: "FAILED", tone: .error)
        }
        lights = (state.stopped ? [StatusLight(label: "BRIDGE", word: "STOPPED", tone: .error)] : []) + [controller, feedback]
        line = lights.map { "\($0.label) ● \($0.word)" }.joined(separator: " · ") + " · DECK [\(state.deck)]"
        icon = if lights.contains(where: { $0.tone == .error }) { .error }
            else if lights.allSatisfy({ $0.tone == .live }) { .ok }
            else { .attention }
        lastDropout = state.lastDropout.map { "LAST DROPOUT: " + $0 }
    }
}

extension StatusLight.Tone {
    public var color: RGB {
        switch self {
        case .live: Palette.live
        case .idle: Palette.caption
        case .attention: Palette.attention
        case .error: Palette.error
        }
    }
}
