/// What the bridge knows about itself, as the menu needs it. The app fills this from the Coordinator's status and the
/// feedback listener; it has no CoreMIDI or SwiftUI types, so the wording can be tested here.
/// Why a controller disconnected, as the panel needs it (#91). The app maps Core's DisconnectReason onto this, one to one.
extension BridgeState {
    public enum Disconnect: Equatable, Sendable {
        case unplugged, sendFailed, inputFailed, deviceChanged, removed, stopped
    }
}

extension BridgeState.Controller {
    /// The panel's controller state from what Core reports (#91): connected; unplugged, failed or waiting according to
    /// why it last disconnected, keeping its name; or never connected.
    public init(connected: Bool, profile: String?, lastProfile: String?, lastDisconnect: BridgeState.Disconnect?) {
        if connected {
            self = .connected(profile: profile ?? lastProfile ?? "Controller")
            return
        }
        switch lastDisconnect {
        case .unplugged: self = .unplugged(profile: lastProfile)
        case .sendFailed, .inputFailed: self = .failed(profile: lastProfile)
        case .deviceChanged: self = .waiting(profile: lastProfile)
        case .removed, .stopped, nil: self = .notConnected
        }
    }
}

public struct BridgeState: Equatable, Sendable {
    public enum Controller: Equatable, Sendable {
        case connected(profile: String)
        /// Connected earlier this session, now gone (#66): orange, so an unplug mid-set is noticed.
        case unplugged(profile: String?)
        /// Never connected since launch.
        case notConnected
        /// Connected, then sending or reading failed (#91): orange MIDI ERROR, not UNPLUGGED.
        case failed(profile: String?)
        /// Settings chose other devices, and they aren't there (yet) (#91): gray WAITING.
        case waiting(profile: String?)
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
    /// When Syndicate's feedback last stopped (#21), as the time to show, such as "21:14".
    public var lastDropout: String?

    /// The deck is Syndicate's tempo master (#53). Not a problem, so it never changes the icon.
    public var master: Bool
    /// The built-in demo controller is running (#64), not real hardware.
    public var demo: Bool
    /// The last connect, disconnect or unplug, for the header's subtitle.
    public var lastEvent: String?
    /// Further controllers after the first (#25), each with its own deck and last event.
    public var others: [ControllerEntry]

    public struct ControllerEntry: Equatable, Sendable {
        public var controller: Controller
        public var deck: Int
        public var lastEvent: String?
        /// The controller follows its own deck layers (#79), so `deck` is its active layer's.
        public var followsLayers: Bool

        public init(controller: Controller, deck: Int, lastEvent: String? = nil, followsLayers: Bool = false) {
            self.controller = controller
            self.deck = deck
            self.lastEvent = lastEvent
            self.followsLayers = followsLayers
        }
    }

    /// The first controller follows its own deck layers (#79).
    public var followsLayers = false

    public init(controller: Controller, feedback: Feedback, deck: Int, stopped: Bool = false, lastDropout: String? = nil,
                master: Bool = false, demo: Bool = false, lastEvent: String? = nil, others: [ControllerEntry] = [],
                followsLayers: Bool = false) {
        self.followsLayers = followsLayers
        self.demo = demo
        self.lastEvent = lastEvent
        self.others = others
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

/// The panel's header: what controller this is, and what last happened to it.
public struct StatusHeader: Equatable, Sendable {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }
}

/// One controller in the panel: who it is, whether it's connected, and its deck.
public struct ControllerBlock: Equatable, Sendable {
    public var header: StatusHeader
    public var light: StatusLight
    public var deck: Int
    /// The controller picks the deck itself, through its own layers (#79): the panel shows it, not a picker.
    public var followsLayers: Bool

    public init(header: StatusHeader, light: StatusLight, deck: Int, followsLayers: Bool = false) {
        self.header = header
        self.light = light
        self.deck = deck
        self.followsLayers = followsLayers
    }

    /// Said beside the deck when the controller's layers pick it.
    public var deckNote: String? { followsLayers ? "Following controller layers" : nil }
}

/// A small caption over a value, such as LAST DROPOUT over 21:14. The caption is natural case; the view uppercases it.
public struct CaptionedValue: Equatable, Sendable {
    public var caption: String
    public var value: String

    public init(caption: String, value: String) {
        self.caption = caption
        self.value = value
    }
}

/// The deck picker: usable, shown but off with a reason, or not shown.
public enum DeckPickerState: Equatable, Sendable {
    case enabled
    case disabled(reason: String)
    case hidden
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
    /// The panel's header: the first controller's name and its last event (#66).
    public var header: StatusHeader
    /// One block per controller: its header, its CONTROLLER light and its deck (#66, #25).
    public var blocks: [ControllerBlock]
    /// The parts of `line`, for the status bar to draw in their tones.
    public var lineParts: [StatusLinePart]
    public var icon: IconState
    /// The orange MASTER light, apart from `lights` so it never counts toward the icon (#53).
    public var master: StatusLight?
    /// LAST DROPOUT and its time, once Syndicate's feedback has stopped at least once (#21, #66).
    public var lastDropout: CaptionedValue?
    /// Whether Quit asks before quitting (#66).
    public var quitAsks: Bool
    /// Whether the deck picker can be used, and why not (#90).
    public var deckPicker: DeckPickerState

    /// How many characters the panel's status bar holds without truncating (360 pt, 10 pt semibold caps).
    public static let lineBudget = 56

    public init(_ state: BridgeState, lineBudget: Int = StatusPresentation.lineBudget) {
        let controller = Self.light(for: state.controller)
        blocks = ([BridgeState.ControllerEntry(controller: state.controller, deck: state.deck, lastEvent: state.lastEvent,
                                               followsLayers: state.followsLayers)] + state.others)
            .map {
                ControllerBlock(header: Self.header(for: $0.controller, lastEvent: $0.lastEvent), light: Self.light(for: $0.controller),
                                deck: $0.deck, followsLayers: $0.followsLayers)
            }
        header = blocks[0].header
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
            + [(StatusLinePart(label: nil, word: "DECK " + blocks.map { "[\($0.deck)]" }.joined(separator: " "), tone: .idle), 4)]
            + (state.master ? [(StatusLinePart(label: nil, word: "MASTER", tone: .attention), 3)] : [])
        lineParts = Self.fit(parts, budget: lineBudget)
        line = lineParts.map(\.text).joined(separator: Self.separator)
        // Every controller counts: an unplugged second one needs a look too.
        let allLights = lights + blocks.dropFirst().map(\.light)
        icon = if allLights.contains(where: { $0.tone == .error }) { .error }
            else if allLights.allSatisfy({ $0.tone == .live }) { .ok }
            else { .attention }
        lastDropout = state.lastDropout.map { CaptionedValue(caption: "Last dropout", value: $0) }
        // Quitting stops a working set only while feedback is live, so that's when Quit asks first (#66).
        if case .live = state.feedback { quitAsks = true } else { quitAsks = false }
        // In demo mode a click would be held for the real controller and jump its deck later, unasked (#90).
        deckPicker = state.stopped ? .hidden
            : state.demo ? .disabled(reason: "Demo controller is on, so the deck stays put.") : .enabled
    }

    static let separator = " · "

    /// The label is always CONTROLLER, so the lights don't shift sideways; the name is in the header (#66).
    static func light(for controller: BridgeState.Controller) -> StatusLight {
        switch controller {
        case .connected: StatusLight(label: "CONTROLLER", word: "CONNECTED", tone: .live)
        case .unplugged: StatusLight(label: "CONTROLLER", word: "UNPLUGGED", tone: .attention)
        case .notConnected: StatusLight(label: "CONTROLLER", word: "NOT CONNECTED", tone: .idle)
        case .failed: StatusLight(label: "CONTROLLER", word: "MIDI ERROR", tone: .attention)
        case .waiting: StatusLight(label: "CONTROLLER", word: "WAITING", tone: .idle)
        }
    }

    static func header(for controller: BridgeState.Controller, lastEvent: String?) -> StatusHeader {
        switch controller {
        case .connected(let profile): StatusHeader(title: profile, subtitle: lastEvent)
        case .unplugged(let profile): StatusHeader(title: profile ?? "Controller unplugged", subtitle: lastEvent)
        case .notConnected: StatusHeader(title: "No controller", subtitle: lastEvent)
        case .failed(let profile), .waiting(let profile): StatusHeader(title: profile ?? "No controller", subtitle: lastEvent)
        }
    }

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
