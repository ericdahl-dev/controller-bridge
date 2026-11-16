import Foundation

/// The LC6000 mapping: note and CC numbers, OSC settings and LED colors.
///
/// The bundled default is ported value for value from the Python bridge's default_mapping.toml, with the same
/// section and key names. Note and CC numbers come from Denon's "LC6000 PRIME MIDI Specification v1.0"; the values
/// marked PROVISIONAL there (jog CCs, pitch direction, the color table layout and the LED notes) still need checking
/// on hardware.
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

        public init(input: String, output: String, channel: Int) {
            self.input = input
            self.output = output
            self.channel = channel
        }
    }

    public struct OSC: Equatable, Sendable, Codable {
        public var host: String
        public var port: Int
        public var root: String
        public var feedbackHost: String
        public var feedbackPort: Int

        enum CodingKeys: String, CodingKey {
            case host, port, root
            case feedbackHost = "feedback_host"
            case feedbackPort = "feedback_port"
        }

        public init(host: String, port: Int, root: String, feedbackHost: String, feedbackPort: Int) {
            self.host = host
            self.port = port
            self.root = root
            self.feedbackHost = feedbackHost
            self.feedbackPort = feedbackPort
        }
    }

    public struct Deck: Equatable, Sendable, Codable {
        /// The Syndicate deck, 1-4.
        public var number: Int

        public init(number: Int) { self.number = number }
    }

    public struct Jog: Equatable, Sendable, Codable {
        public var ccs: [Int]
        public var bendReleaseMs: Int
        public var seekSecondsPerTick: Double
        public var seekFallbackTicksPerBeat: Int
        public var requireTouch: Bool

        enum CodingKeys: String, CodingKey {
            case ccs
            case bendReleaseMs = "bend_release_ms"
            case seekSecondsPerTick = "seek_seconds_per_tick"
            case seekFallbackTicksPerBeat = "seek_fallback_ticks_per_beat"
            case requireTouch = "require_touch"
        }

        public init(ccs: [Int], bendReleaseMs: Int, seekSecondsPerTick: Double, seekFallbackTicksPerBeat: Int, requireTouch: Bool) {
            self.ccs = ccs
            self.bendReleaseMs = bendReleaseMs
            self.seekSecondsPerTick = seekSecondsPerTick
            self.seekFallbackTicksPerBeat = seekFallbackTicksPerBeat
            self.requireTouch = requireTouch
        }
    }

    public struct Pitch: Equatable, Sendable, Codable {
        public var msbCC: Int
        public var lsbCC: Int
        public var invert: Bool
        public var deadZone: Double

        enum CodingKeys: String, CodingKey {
            case msbCC = "msb_cc"
            case lsbCC = "lsb_cc"
            case invert
            case deadZone = "dead_zone"
        }

        public init(msbCC: Int, lsbCC: Int, invert: Bool, deadZone: Double) {
            self.msbCC = msbCC
            self.lsbCC = lsbCC
            self.invert = invert
            self.deadZone = deadZone
        }
    }

    public struct Needle: Equatable, Sendable, Codable {
        public var cc: Int
        public var touchNote: Int
        public var requireTouch: Bool

        enum CodingKeys: String, CodingKey {
            case cc
            case touchNote = "touch_note"
            case requireTouch = "require_touch"
        }

        public init(cc: Int, touchNote: Int, requireTouch: Bool) {
            self.cc = cc
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

        enum CodingKeys: String, CodingKey {
            case pitchCenter = "pitch_center"
            case ring
            case ringColor = "ring_color"
            case rollPadColor = "roll_pad_color"
            case loopPadColor = "loop_pad_color"
            case dimUnlitButtons = "dim_unlit_buttons"
        }

        public init(pitchCenter: Int, ring: Int, ringColor: [Int], rollPadColor: [Int], loopPadColor: [Int], dimUnlitButtons: Bool) {
            self.pitchCenter = pitchCenter
            self.ring = ring
            self.ringColor = ringColor
            self.rollPadColor = rollPadColor
            self.loopPadColor = loopPadColor
            self.dimUnlitButtons = dimUnlitButtons
        }
    }

    /// The mapping that ships with the app.
    public static func bundledDefault() throws -> Mapping {
        try JSONDecoder().decode(Mapping.self, from: defaultJSON())
    }

    /// The bundled default with a user mapping file merged over it, as the Python config merge does: objects merge
    /// key by key, at any depth; anything else (a list, a number, a string) replaces the default whole.
    public static func bundledDefault(overriddenBy override: Data) throws -> Mapping {
        let base = try JSONSerialization.jsonObject(with: defaultJSON())
        let user = try JSONSerialization.jsonObject(with: override)
        let merged = try JSONSerialization.data(withJSONObject: merge(base, user))
        return try JSONDecoder().decode(Mapping.self, from: merged)
    }

    private static func merge(_ base: Any, _ override: Any) -> Any {
        guard var out = base as? [String: Any], let override = override as? [String: Any] else { return override }
        for (key, value) in override {
            out[key] = out[key].map { merge($0, value) } ?? value
        }
        return out
    }

    static func defaultJSON() throws -> Data {
        guard let url = Bundle.module.url(forResource: "default_mapping", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
