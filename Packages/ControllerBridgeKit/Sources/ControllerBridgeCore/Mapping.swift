import Foundation

/// The LC6000 mapping: note and CC numbers, OSC settings and LED colors.
///
/// The bundled default is ported value for value from the Python bridge's default_mapping.toml (removed in #30), with the same
/// section and key names. Note and CC numbers come from Denon's "LC6000 PRIME MIDI Specification v1.0" and were
/// checked on a real unit (2026-11-15, #12, #103). What's still PROVISIONAL is listed in the Kit README.
public struct Mapping: Equatable, Sendable, Codable {
    public var midi: MIDI
    public var osc: OSC
    public var deck: Deck
    public var jog: Jog
    public var pitch: Pitch
    public var needle: Needle
    public var browse: Browse
    public var notes: Notes
    public var leds: LEDs

    public struct MIDI: Equatable, Sendable, Codable {
        public var input: String
        public var output: String
        /// 1-16.
        public var channel: Int
        /// Notes the controller sends on its own, such as the LC6000's idle heartbeat on note 52 (#103): dropped
        /// before anything sees them.
        public var ignoreNotes: [Int]
        /// The controller's own deck layers (#79): each MIDI channel drives a Syndicate deck. Empty for a controller
        /// without layers.
        public var layers: [Layer]
        /// The note the controller sends on a layer's channel as it becomes active (127) or inactive (0).
        public var layerNote: Int?

        enum CodingKeys: String, CodingKey {
            case input, output, channel, layers
            case ignoreNotes = "ignore_notes"
            case layerNote = "layer_note"
        }

        public init(
            input: String, output: String, channel: Int, ignoreNotes: [Int] = [], layers: [Layer] = [], layerNote: Int? = nil
        ) {
            self.input = input
            self.output = output
            self.channel = channel
            self.ignoreNotes = ignoreNotes
            self.layers = layers
            self.layerNote = layerNote
        }

        /// `ignore_notes`, `layers` and `layer_note` may be left out: nothing ignored, no layers.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try container.decode(String.self, forKey: .input)
            output = try container.decode(String.self, forKey: .output)
            channel = try container.decode(Int.self, forKey: .channel)
            ignoreNotes = try container.decodeIfPresent([Int].self, forKey: .ignoreNotes) ?? []
            layers = try container.decodeIfPresent([Layer].self, forKey: .layers) ?? []
            layerNote = try container.decodeIfPresent(Int.self, forKey: .layerNote)
        }
    }

    /// One of a controller's deck layers: its MIDI channel, 1-16, and the Syndicate deck it drives, 1-4.
    public struct Layer: Equatable, Sendable, Codable {
        public var channel: Int
        public var deck: Int

        public init(channel: Int, deck: Int) {
            self.channel = channel
            self.deck = deck
        }
    }

    public struct OSC: Equatable, Sendable, Codable {
        public var host: String
        public var port: Int
        public var root: String
        public var feedbackHost: String
        public var feedbackPort: Int
        /// After this long with no feedback, the bridge asks Syndicate to resend, to tell a quiet Syndicate from a
        /// gone one. Syndicate sends nothing while every deck is paused and nothing changes.
        public var feedbackQuietMs: Int
        /// How long that request may go unanswered before feedback counts as stopped.
        public var feedbackAnswerMs: Int

        enum CodingKeys: String, CodingKey {
            case host, port, root
            case feedbackHost = "feedback_host"
            case feedbackPort = "feedback_port"
            case feedbackQuietMs = "feedback_quiet_ms"
            case feedbackAnswerMs = "feedback_answer_ms"
        }

        public init(
            host: String, port: Int, root: String, feedbackHost: String, feedbackPort: Int,
            feedbackQuietMs: Int, feedbackAnswerMs: Int
        ) {
            self.host = host
            self.port = port
            self.root = root
            self.feedbackHost = feedbackHost
            self.feedbackPort = feedbackPort
            self.feedbackQuietMs = feedbackQuietMs
            self.feedbackAnswerMs = feedbackAnswerMs
        }
    }

    public struct Deck: Equatable, Sendable, Codable {
        /// The Syndicate deck, 1-4.
        public var number: Int

        public init(number: Int) { self.number = number }
    }

    /// The jog wheel as a 14-bit platter position that counts up going forward and wraps at 16384 (#103). Movement
    /// is the change in position, scaled per platter revolution.
    public struct Jog: Equatable, Sendable, Codable {
        public var msbCC: Int
        public var lsbCC: Int
        /// Position counts in one full platter turn: about 3552 measured on the LC6000 (#103), so 3600.
        public var countsPerRev: Int
        public var bendReleaseMs: Int
        /// While paused, how far one platter turn moves the playhead.
        public var seekSecondsPerRev: Double
        /// While paused with no track length, how many beats one platter turn skips.
        public var beatsPerRev: Double
        public var requireTouch: Bool

        enum CodingKeys: String, CodingKey {
            case msbCC = "msb_cc"
            case lsbCC = "lsb_cc"
            case countsPerRev = "counts_per_rev"
            case bendReleaseMs = "bend_release_ms"
            case seekSecondsPerRev = "seek_seconds_per_rev"
            case beatsPerRev = "beats_per_rev"
            case requireTouch = "require_touch"
        }

        public init(
            msbCC: Int, lsbCC: Int, countsPerRev: Int, bendReleaseMs: Int, seekSecondsPerRev: Double, beatsPerRev: Double,
            requireTouch: Bool
        ) {
            self.msbCC = msbCC
            self.lsbCC = lsbCC
            self.countsPerRev = countsPerRev
            self.bendReleaseMs = bendReleaseMs
            self.seekSecondsPerRev = seekSecondsPerRev
            self.beatsPerRev = beatsPerRev
            self.requireTouch = requireTouch
        }
    }

    public struct Pitch: Equatable, Sendable, Codable {
        public var msbCC: Int
        public var lsbCC: Int
        public var invert: Bool
        public var deadZone: Double
        /// After a load or an outside tempo change, ignore the fader until it meets Syndicate's slider (#22).
        public var pickup: Bool
        /// How close, on the -1...+1 range, counts as meeting it.
        public var pickupTolerance: Double

        enum CodingKeys: String, CodingKey {
            case msbCC = "msb_cc"
            case lsbCC = "lsb_cc"
            case invert
            case deadZone = "dead_zone"
            case pickup
            case pickupTolerance = "pickup_tolerance"
        }

        public init(msbCC: Int, lsbCC: Int, invert: Bool, deadZone: Double, pickup: Bool, pickupTolerance: Double) {
            self.msbCC = msbCC
            self.lsbCC = lsbCC
            self.invert = invert
            self.deadZone = deadZone
            self.pickup = pickup
            self.pickupTolerance = pickupTolerance
        }

        /// `pickup` and `pickup_tolerance` may be left out of a profile or mapping file: they default to on and 0.02.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            msbCC = try container.decode(Int.self, forKey: .msbCC)
            lsbCC = try container.decode(Int.self, forKey: .lsbCC)
            invert = try container.decode(Bool.self, forKey: .invert)
            deadZone = try container.decode(Double.self, forKey: .deadZone)
            pickup = try container.decodeIfPresent(Bool.self, forKey: .pickup) ?? true
            pickupTolerance = try container.decodeIfPresent(Double.self, forKey: .pickupTolerance) ?? 0.02
        }
    }

    /// The Needle Drop strip: a 14-bit position on an MSB/LSB CC pair (#103), and its touch note.
    public struct Needle: Equatable, Sendable, Codable {
        public var msbCC: Int
        public var lsbCC: Int
        public var touchNote: Int
        public var requireTouch: Bool

        enum CodingKeys: String, CodingKey {
            case msbCC = "msb_cc"
            case lsbCC = "lsb_cc"
            case touchNote = "touch_note"
            case requireTouch = "require_touch"
        }

        public init(msbCC: Int, lsbCC: Int, touchNote: Int, requireTouch: Bool) {
            self.msbCC = msbCC
            self.lsbCC = lsbCC
            self.touchNote = touchNote
            self.requireTouch = requireTouch
        }
    }

    public struct Browse: Equatable, Sendable, Codable {
        public var selectTurnCC: Int
        public var autoLoopSizeCC: Int

        enum CodingKeys: String, CodingKey {
            case selectTurnCC = "select_turn_cc"
            case autoLoopSizeCC = "auto_loop_size_cc"
        }

        public init(selectTurnCC: Int, autoLoopSizeCC: Int) {
            self.selectTurnCC = selectTurnCC
            self.autoLoopSizeCC = autoLoopSizeCC
        }
    }

    /// Button notes by name (as in the Python mapping), plus the eight pad notes.
    public struct Notes: Equatable, Sendable, Codable {
        public var buttons: [String: Int]
        public var pads: [Int]

        public init(buttons: [String: Int], pads: [Int]) {
            self.buttons = buttons
            self.pads = pads
        }

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            pads = try container.decode([Int].self, forKey: Key(stringValue: "pads"))
            buttons = [:]
            for key in container.allKeys where key.stringValue != "pads" {
                buttons[key.stringValue] = try container.decode(Int.self, forKey: key)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for (name, note) in buttons { try container.encode(note, forKey: Key(stringValue: name)) }
            try container.encode(pads, forKey: Key(stringValue: "pads"))
        }
    }

    public struct LEDs: Equatable, Sendable, Codable {
        public var pitchCenter: Int
        public var ring: Int
        public var ringColor: [Int]
        public var rollPadColor: [Int]
        public var loopPadColor: [Int]
        public var dimUnlitButtons: Bool
        /// Pulse the platter ring on Syndicate's master clock: never, on every beat, or on the downbeat only.
        public var beatPulse: BeatPulse
        /// How long the ring stays lit after each pulsed beat.
        public var pulseMs: Int
        /// What Syndicate's LEDs show once feedback has stopped: dim, or off.
        public var staleIdle: StaleIdle

        public enum BeatPulse: String, Equatable, Sendable, Codable, CaseIterable {
            case off, beat, downbeat
        }

        public enum StaleIdle: String, Equatable, Sendable, Codable, CaseIterable {
            case dim, off
        }

        enum CodingKeys: String, CodingKey {
            case pitchCenter = "pitch_center"
            case ring
            case ringColor = "ring_color"
            case rollPadColor = "roll_pad_color"
            case loopPadColor = "loop_pad_color"
            case dimUnlitButtons = "dim_unlit_buttons"
            case beatPulse = "beat_pulse"
            case pulseMs = "pulse_ms"
            case staleIdle = "stale_idle"
        }

        public init(
            pitchCenter: Int, ring: Int, ringColor: [Int], rollPadColor: [Int], loopPadColor: [Int], dimUnlitButtons: Bool,
            beatPulse: BeatPulse, pulseMs: Int, staleIdle: StaleIdle
        ) {
            self.pitchCenter = pitchCenter
            self.ring = ring
            self.ringColor = ringColor
            self.rollPadColor = rollPadColor
            self.loopPadColor = loopPadColor
            self.dimUnlitButtons = dimUnlitButtons
            self.beatPulse = beatPulse
            self.pulseMs = pulseMs
            self.staleIdle = staleIdle
        }
    }

    /// The mapping that ships with the app.
    public static func bundledDefault() throws -> Mapping {
        try checked(defaultJSON())
    }

    /// A whole mapping body, through the full check (#24) first: every problem at once, or the decoded mapping.
    static func checked(_ json: Data, schema: OrderedJSON? = nil) throws -> Mapping {
        let problems: [String]
        do { problems = Self.problems(in: try OrderedJSON(parsing: json), schema: schema) } catch { problems = ["\(error)"] }
        guard problems.isEmpty else { throw MappingError.invalid(problems) }
        do {
            return try JSONDecoder().decode(Mapping.self, from: json)
        } catch let error as DecodingError {
            // The check runs first, so this shouldn't happen; if it does, the DJ still gets words, not a dump (#92).
            throw MappingError.invalid([Self.describe(error)])
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context? = switch error {
        case .dataCorrupted(let c), .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c): c
        @unknown default: nil
        }
        let path = context?.codingPath.map(\.stringValue).joined(separator: ".") ?? ""
        return (path.isEmpty ? "mapping" : path) + ": the value can't be used here"
    }

    /// The bundled default with a user mapping file merged over it, as the Python config merge does: objects merge
    /// key by key, at any depth; anything else (a list, a number, a string) replaces the default whole. Bad JSON or
    /// bad values throw `MappingError` with readable problems.
    public static func bundledDefault(overriddenBy override: Data) throws -> Mapping {
        let user: OrderedJSON
        do { user = try OrderedJSON(parsing: override) } catch { throw MappingError.invalid(["\(error)"]) }
        let base = try OrderedJSON(parsing: defaultJSON())
        return try checked(merge(base, user).data())
    }

    /// The default mapping: the body of the bundled LC6000 profile, the first controller this app supports.
    static func defaultJSON() throws -> Data {
        try ControllerProfile.mappingJSON(of: ControllerProfile.bundledFile("denon-lc6000-prime"))
    }
}

/// A mapping the bridge can't run with. Each problem names the key and what was expected.
public enum MappingError: Error, Equatable {
    case invalid([String])
}
