import Foundation

// The capture file (#185): what a guided capture records about one controller, as versioned JSON shared by the app
// and the web capture (#190). Keys are snake_case like a profile, and MIDI is written as spaced hex ("90 01 7F").

/// One capture of one controller.
public struct CaptureFile: Codable, Equatable, Sendable {
    /// The format version. A reader refuses a version it doesn't know.
    public var format: Int
    public var appVersion: String
    /// The controller's name as the system reports it.
    public var device: String
    public var ports: CapturePorts
    /// The only free text in the file, and only what the owner chooses to type.
    public var note: String?
    /// The prompt list the capture walked through. Its first prompt is an `idle` one (hands off), which tells the
    /// noise (heartbeats, clock) apart from the controls.
    public var prompts: [CapturePrompt]
    /// Messages that aren't credited to any step, as their status and first data byte ("90 34").
    public var noise: [[UInt8]]
    public var steps: [CaptureStep]

    /// The format this version writes and reads.
    public static let currentFormat = 1

    public init(
        format: Int = currentFormat, appVersion: String, device: String, ports: CapturePorts, note: String? = nil,
        prompts: [CapturePrompt], noise: [[UInt8]] = [], steps: [CaptureStep] = []
    ) {
        self.format = format
        self.appVersion = appVersion
        self.device = device
        self.ports = ports
        self.note = note
        self.prompts = prompts
        self.noise = noise
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey {
        case format, appVersion = "app_version", device, ports, note, prompts, noise, steps
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        guard format == Self.currentFormat else { throw CaptureFileError.unsupportedFormat(format) }
        appVersion = try c.decode(String.self, forKey: .appVersion)
        device = try c.decode(String.self, forKey: .device)
        ports = try c.decode(CapturePorts.self, forKey: .ports)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        prompts = try c.decode([CapturePrompt].self, forKey: .prompts)
        noise = try c.decode([String].self, forKey: .noise).map(Hex.bytes)
        steps = try c.decode([CaptureStep].self, forKey: .steps)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encode(device, forKey: .device)
        try c.encode(ports, forKey: .ports)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(prompts, forKey: .prompts)
        try c.encode(noise.map(Hex.string), forKey: .noise)
        try c.encode(steps, forKey: .steps)
    }

    public static func decode(_ data: Data) throws -> CaptureFile {
        try JSONDecoder().decode(CaptureFile.self, from: data)
    }

    /// Pretty-printed with sorted keys, so two captures diff cleanly.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Why a capture file can't be read.
public enum CaptureFileError: Error, Equatable, CustomStringConvertible {
    case unsupportedFormat(Int)

    public var description: String {
        switch self {
        case .unsupportedFormat(let format):
            "This capture file is format \(format); this version reads format \(CaptureFile.currentFormat). Update DeckBridge."
        }
    }
}

/// The controller's MIDI port names.
public struct CapturePorts: Codable, Equatable, Sendable {
    public var input: [String]
    public var output: [String]

    public init(input: [String], output: [String]) {
        self.input = input
        self.output = output
    }
}

/// What a step asks the owner to do.
public enum CaptureGesture: String, Codable, Sendable {
    /// Touch nothing: whatever arrives is noise.
    case idle
    /// Press and release a button or pad.
    case press
    /// Move a fader or knob, in the direction the prompt says.
    case move
    /// Turn an encoder or the jog wheel.
    case turn
}

/// One step of the prompt list.
public struct CapturePrompt: Codable, Equatable, Sendable {
    /// A stable id, such as "deck1.play".
    public var id: String
    public var text: String
    public var gesture: CaptureGesture
    /// The prompt this one repeats with Shift held.
    public var shiftedOf: String?

    public init(id: String, text: String, gesture: CaptureGesture, shiftedOf: String? = nil) {
        self.id = id
        self.text = text
        self.gesture = gesture
        self.shiftedOf = shiftedOf
    }

    enum CodingKeys: String, CodingKey { case id, text, gesture, shiftedOf = "shifted_of" }
}

/// What the owner did with a step.
public enum StepStatus: String, Codable, Sendable {
    case confirmed, skipped
}

/// One step as recorded: the raw messages and what they mean.
public struct CaptureStep: Codable, Equatable, Sendable {
    public var prompt: String
    public var status: StepStatus
    public var messages: [CaptureMessage]
    public var controls: [ControlFacts]
    public var leds: [LEDAnswer]
    /// For a step repeated with Shift held, how it differs from the step it repeats.
    public var shift: ShiftLayer?

    public init(
        prompt: String, status: StepStatus, messages: [CaptureMessage] = [], controls: [ControlFacts] = [],
        leds: [LEDAnswer] = [], shift: ShiftLayer? = nil
    ) {
        self.prompt = prompt
        self.status = status
        self.messages = messages
        self.controls = controls
        self.leds = leds
        self.shift = shift
    }
}

/// One raw MIDI message, `t` milliseconds after its step's first message. No clock time is kept.
public struct CaptureMessage: Codable, Equatable, Sendable {
    public var t: Int
    public var bytes: [UInt8]

    public init(t: Int, bytes: [UInt8]) {
        self.t = t
        self.bytes = bytes
    }

    enum CodingKeys: String, CodingKey { case t, midi }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Int.self, forKey: .t)
        bytes = try Hex.bytes(c.decode(String.self, forKey: .midi))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(Hex.string(bytes), forKey: .midi)
    }
}

/// What kind of MIDI message a control sends.
public enum ControlKind: String, Codable, Sendable {
    case note, cc
    case pitchBend = "pitch_bend"
}

/// How a note control says it was released.
public enum NoteRelease: String, Codable, Sendable {
    case noteOff = "note_off"
    case noteOnZero = "note_on_zero"
}

/// How a CC control encodes its value. The relative names match the profile's `midi.encoder_format` (#193).
public enum Encoding: String, Codable, Sendable {
    case absolute
    case twosComplement = "twos_complement"
    case offset64 = "offset_64"
    case signMagnitude = "sign_magnitude"
}

/// What a step's messages say about one control. Channels are 1-based, as in a profile.
public struct ControlFacts: Codable, Equatable, Sendable {
    public var kind: ControlKind
    public var channel: Int
    /// The note or CC number. Pitch bend has none.
    public var number: Int?
    /// The LSB CC of a 14-bit pair (`number` is the MSB).
    public var lsb: Int?
    public var encoding: Encoding?
    public var release: NoteRelease?
    /// The first and last values seen, in order, so a gesture's direction can be read ("bottom to top" ending at 0
    /// means up is 0). 14-bit for a pair or pitch bend.
    public var first: Int
    public var last: Int
    public var min: Int
    public var max: Int

    public init(
        kind: ControlKind, channel: Int, number: Int? = nil, lsb: Int? = nil, encoding: Encoding? = nil,
        release: NoteRelease? = nil, first: Int, last: Int, min: Int, max: Int
    ) {
        self.kind = kind
        self.channel = channel
        self.number = number
        self.lsb = lsb
        self.encoding = encoding
        self.release = release
        self.first = first
        self.last = last
        self.min = min
        self.max = max
    }
}

/// How a step repeated with Shift held differs from the step it repeats.
public struct ShiftLayer: Codable, Equatable, Sendable {
    /// The prompt id of the unshifted step.
    public var of: String
    public var channelOffset: Int
    public var numberOffset: Int

    public init(of: String, channelOffset: Int, numberOffset: Int) {
        self.of = of
        self.channelOffset = channelOffset
        self.numberOffset = numberOffset
    }

    enum CodingKeys: String, CodingKey { case of, channelOffset = "channel_offset", numberOffset = "number_offset" }
}

/// The owner's answer to one LED probe message.
public struct LEDAnswer: Codable, Equatable, Sendable {
    public var sent: [UInt8]
    public var lit: Bool
    /// The color the owner named, if it lit.
    public var color: String?

    public init(sent: [UInt8], lit: Bool, color: String? = nil) {
        self.sent = sent
        self.lit = lit
        self.color = color
    }

    enum CodingKeys: String, CodingKey { case sent, lit, color }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = try Hex.bytes(c.decode(String.self, forKey: .sent))
        lit = try c.decode(Bool.self, forKey: .lit)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Hex.string(sent), forKey: .sent)
        try c.encode(lit, forKey: .lit)
        try c.encodeIfPresent(color, forKey: .color)
    }
}

/// Spaced uppercase hex, as MIDI Monitor shows it.
enum Hex {
    struct Invalid: Error, CustomStringConvertible {
        var text: String
        var description: String { "\"\(text)\" isn't MIDI hex like \"90 01 7F\"" }
    }

    static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func bytes(_ text: String) throws -> [UInt8] {
        try text.split(separator: " ").map {
            guard $0.count == 2, let byte = UInt8($0, radix: 16) else { throw Invalid(text: text) }
            return byte
        }
    }
}
