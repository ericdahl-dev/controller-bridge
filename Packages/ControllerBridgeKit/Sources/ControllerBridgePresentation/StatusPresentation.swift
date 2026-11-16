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

    /// The deck is Syndicate's tempo master (#53). Not a problem, so it never changes the icon.
    public var master: Bool
    /// The built-in demo controller is running (#64), not real hardware.
    public var demo: Bool

    public init(controller: Controller, feedback: Feedback, deck: Int, stopped: Bool = false, lastDropout: String? = nil,
                master: Bool = false, demo: Bool = false) {
        self.demo = demo
        self.controller = controller
        self.feedback = feedback
        self.deck = deck
        self.stopped = stopped
        self.lastDropout = lastDropout
        self.master = master
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

/// One part of the status bar: "LABEL ● WORD", or a bare word such as "DECK [1]" or "MASTER".
public struct StatusLinePart: Equatable, Sendable {
    public var label: String?
    public var word: String
    public var tone: StatusLight.Tone

    public init(label: String?, word: String, tone: StatusLight.Tone) {
        self.label = label
        self.word = word
        self.tone = tone
    }

    public var text: String { label.map { "\($0) ● \(word)" } ?? word }
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
    /// The parts of `line`, for the status bar to draw in their tones.
    public var lineParts: [StatusLinePart]
    public var icon: IconState
    /// The orange MASTER light, apart from `lights` so it never counts toward the icon (#53).
    public var master: StatusLight?
    /// "LAST DROPOUT: …" for the panel, once Syndicate's feedback has stopped at least once (#21).
    public var lastDropout: String?

    /// How many characters the panel's status bar holds without truncating (360 pt, 10 pt semibold caps).
    public static let lineBudget = 60

    public init(_ state: BridgeState, lineBudget: Int = StatusPresentation.lineBudget) {
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
        // A bridge that couldn't start has nothing starting or connecting: the BRIDGE light alone tells the truth (#66).
        lights = state.stopped ? [StatusLight(label: "BRIDGE", word: "STOPPED", tone: .error)]
            // Orange and first, and it keeps the icon on attention: DEMO must never be mistaken for real hardware.
            : (state.demo ? [StatusLight(label: "DEMO", word: "CONTROLLER", tone: .attention)] : []) + [controller, feedback]
        master = state.master ? StatusLight(label: "TEMPO", word: "MASTER", tone: .attention) : nil
        // The status bar: each light, then the deck, then MASTER, cut to whole parts that fit (#66).
        let parts = lights.map { (StatusLinePart(label: $0.label, word: $0.word, tone: $0.tone), Self.priority(of: $0, controller: controller)) }
            + [(StatusLinePart(label: nil, word: "DECK [\(state.deck)]", tone: .idle), 4)]
            + (state.master ? [(StatusLinePart(label: nil, word: "MASTER", tone: .attention), 3)] : [])
        lineParts = Self.fit(parts, budget: lineBudget)
        line = lineParts.map(\.text).joined(separator: Self.separator)
        icon = if lights.contains(where: { $0.tone == .error }) { .error }
            else if lights.allSatisfy({ $0.tone == .live }) { .ok }
            else { .attention }
        lastDropout = state.lastDropout.map { "LAST DROPOUT: " + $0 }
    }

    static let separator = " · "

    /// Lower keeps longer: DEMO and error lights, then the controller, feedback, MASTER, and DECK last.
    private static func priority(of light: StatusLight, controller: StatusLight) -> Int {
        if light.tone == .error || light.label == "DEMO" { return 0 }
        return light == controller ? 1 : 2
    }

    /// Drops whole parts, lowest priority first, until the line fits. The most important part always stays whole,
    /// even over the budget: a word is never cut.
    private static func fit(_ parts: [(StatusLinePart, Int)], budget: Int) -> [StatusLinePart] {
        var kept = parts
        func length(_ parts: [(StatusLinePart, Int)]) -> Int {
            parts.map(\.0.text.count).reduce(0, +) + max(0, parts.count - 1) * separator.count
        }
        while kept.count > 1, length(kept) > budget {
            // The last of the lowest-priority parts goes first.
            let worst = kept.indices.max { kept[$0].1 < kept[$1].1 || (kept[$0].1 == kept[$1].1 && $0 < $1) }!
            kept.remove(at: worst)
        }
        return kept.map(\.0)
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
