import ControllerBridgeCapture
import Foundation

/// A draft controller profile from a capture (#189): what the capture shows, set; what it doesn't, listed as a TODO
/// for a person to fill in. Nothing is guessed.
public struct ProfileDraft: Sendable {
    /// The profile file: id, name, device_hints, exclude_hints and the mapping body.
    public var profile: DraftJSON
    /// Keys the draft leaves out, each with how to find its value.
    public var todos: [Todo]

    public struct Todo: Equatable, Sendable {
        /// The key path in the profile ("mapping.notes.play").
        public var key: String
        public var how: String
    }

    public static func make(capture: CaptureFile) -> ProfileDraft {
        var draft = ProfileDraft(profile: .object([]), todos: [])
        draft.identity(capture)
        draft.buttons(capture)
        draft.noise(capture)
        draft.pads(capture)
        draft.jog(capture)
        draft.pitch(capture)
        draft.needle(capture)
        draft.browse(capture)
        return draft
    }

    mutating func set(_ path: String, _ value: DraftJSON) { profile.set(path, value) }

    mutating func todo(_ key: String, _ how: String) {
        if !todos.contains(where: { $0.key == key }) { todos.append(Todo(key: key, how: how)) }
    }

    /// The device names the profile; any input port that carried no control is another port of the same unit, such as
    /// the LC6000's display port, and is excluded so the profile never runs on it.
    private mutating func identity(_ capture: CaptureFile) {
        set("id", .string(Self.slug(capture.device)))
        set("name", .string(capture.device))
        set("device_hints", .array([.string(capture.device)]))
        let used = Set(capture.steps.flatMap { $0.messages.map(\.port) })
        let others = capture.ports.input.indices.filter { !used.contains($0) }.map { DraftJSON.string(capture.ports.input[$0]) }
        set("exclude_hints", .array(others))
        set("mapping.midi.input", .string(capture.device))
        set("mapping.midi.output", .string(capture.device))
    }

    /// The control a step found, or a TODO for `key` saying why there's none.
    mutating func control(_ capture: CaptureFile, _ prompt: String, for key: String) -> ControlFacts? {
        controls(capture, prompt, for: key)?.first
    }

    /// Every control a step found, in the order they came, or nil and a TODO for `key` saying why there's none.
    mutating func controls(_ capture: CaptureFile, _ prompt: String, for key: String) -> [ControlFacts]? {
        guard let step = capture.steps.first(where: { $0.prompt == prompt }) else {
            todo(key, "The capture has no \"\(prompt)\" step. Run the capture again with the current prompt list.")
            return nil
        }
        guard step.status == .confirmed else {
            todo(key, "The owner skipped \"\(prompt)\". Ask them to run that step again, or read it from the docs.")
            return nil
        }
        guard !step.controls.isEmpty else {
            todo(key, "\"\(prompt)\" was confirmed but found no control (only noise came in). Run that step again.")
            return nil
        }
        return step.controls
    }

    /// The buttons a profile names, by the capture prompt that finds each.
    static let buttons: [(prompt: String, name: String)] = [
        ("deck1.play", "play"), ("deck1.cue", "cue"), ("deck1.sync", "sync"), ("deck1.loop_in", "loop_in"),
        ("deck1.loop_out", "loop_out"), ("deck1.auto_loop", "auto_loop"), ("deck1.browse.press", "select_press"),
        ("deck1.shift", "shift"),
    ]

    /// Each button step's note. The deck's channel is Play's; a button on another channel can't be expressed yet.
    private mutating func buttons(_ capture: CaptureFile) {
        var channel: Int?
        for (prompt, name) in Self.buttons {
            let key = "mapping.notes.\(name)"
            guard let control = control(capture, prompt, for: key) else { continue }
            guard control.kind == .note, let note = control.number else {
                let sends = control.kind == .cc ? "CC \(control.number ?? 0)" : "pitch bend"
                todo(key, "\"\(prompt)\" sends \(sends), not a note; profiles take buttons as notes. Needs a new profile key.")
                continue
            }
            if channel == nil {
                channel = control.channel
                set("mapping.midi.channel", .int(control.channel))
            } else if control.channel != channel {
                todo(key, "\"\(prompt)\" is on channel \(control.channel), not the deck's \(channel!). Profiles put buttons on one channel.")
            }
            set(key, .int(note))
        }
    }

    /// Hot cue pads 1–8, in order. Pads on a channel other than the deck's set pads.channel (#224). The capture only
    /// records Hot Cue mode, so per-mode notes (#225) and how the mode is chosen (#198) are always TODOs.
    private mutating func pads(_ capture: CaptureFile) {
        let key = "mapping.notes.pads"
        let controls = (1...8).map { control(capture, "deck1.hotcue\($0)", for: "\(key)[\($0 - 1)]") }
        todos.removeAll { $0.key.hasPrefix("\(key)[") }
        let missing = (1...8).filter { controls[$0 - 1]?.kind != .note }
        if missing.isEmpty, case let pads = controls.compactMap({ $0 }) {
            set(key, .array(pads.map { .int($0.number ?? 0) }))
            let channels = Set(pads.map(\.channel))
            let deck = profile.value(at: "mapping.midi.channel")
            if channels.count > 1 {
                todo("mapping.pads.channel", "The pads came on channels \(channels.sorted()); profiles put all pads on one.")
            } else if let channel = channels.first, deck != .int(channel) {
                set("mapping.pads.channel", .int(channel))
            }
        } else {
            todo(key, "No note for \(missing.map { "deck1.hotcue\($0)" }.joined(separator: ", ")). Run those steps again; notes.pads needs all eight.")
        }
        todo("mapping.pads.mode_notes", "Only if the pads send other notes in Roll, Loop and Slicer modes (#225): press pad 1–8 in each mode and list them. The capture only records Hot Cue mode.")
        todo("mapping.pads.mode_select", "Four mode buttons (\"buttons\") or one that cycles (\"cycle\", #198)? From the manual, or by pressing the mode buttons in MIDI Monitor.")
    }

    /// The jog: an absolute 14-bit pair (the LC6000) or a relative CC (#204), the edge's own CC when it has one, and the
    /// note held while the top is touched. Counts per turn need a measured full turn, so they're always a TODO.
    private mutating func jog(_ capture: CaptureFile) {
        let key = "mapping.jog"
        todo("\(key).counts_per_rev", "Mark the platter, turn it exactly one full turn in MIDI Monitor, and count: position counts for an absolute pair, ticks for a relative jog.")
        guard let top = controls(capture, "deck1.jog.touch", for: key) else { return }
        if let touch = top.first(where: { $0.kind == .note })?.number {
            set("mapping.notes.platter_touch", .int(touch))
        } else {
            todo("mapping.notes.platter_touch", "No note came while the top was touched. If the platter has no touch sensor, jog.require_touch must be false.")
        }
        guard let wheel = top.first(where: { $0.kind == .cc }), let number = wheel.number else {
            todo(key, "The jog didn't send a CC. Check it in MIDI Monitor.")
            return
        }
        let edge = capture.steps.first { $0.prompt == "deck1.jog.edge" && $0.status == .confirmed }?.controls.first { $0.kind == .cc }
        if let lsb = wheel.lsb {
            set("\(key).msb_cc", .int(number))
            set("\(key).lsb_cc", .int(lsb))
            if let edge, edge.number != number {
                todo("\(key).relative_edge_cc", "The edge sent CC \(edge.number ?? 0), apart from the top's pair. Profiles have an edge CC only for a relative jog.")
            }
        } else if wheel.encoding == .absolute {
            todo(key, "The jog sent one absolute 7-bit CC (\(number)); profiles take a 14-bit pair or a relative CC.")
        } else {
            set("\(key).relative_cc", .int(number))
            if let edge, let edgeNumber = edge.number, edgeNumber != number { set("\(key).relative_edge_cc", .int(edgeNumber)) }
            encoderFormat(wheel.encoding, from: "deck1.jog.touch")
        }
    }

    /// The pitch fader, moved top to bottom: a 14-bit pair or one 7-bit CC (#195), inverted when the top gave the
    /// high value (the LC6000's top is 0).
    private mutating func pitch(_ capture: CaptureFile) {
        let key = "mapping.pitch"
        guard let control = control(capture, "deck1.pitch", for: key) else { return }
        guard control.kind == .cc, let msb = control.number else {
            todo(key, "The pitch fader sends pitch bend; profiles take a CC (pitch bend was dropped from v1.2, #199).")
            return
        }
        set("\(key).bits", .int(control.lsb == nil ? 7 : 14))
        set("\(key).msb_cc", .int(msb))
        if let lsb = control.lsb { set("\(key).lsb_cc", .int(lsb)) }
        set("\(key).invert", .bool(control.first > control.last))
    }

    /// The needle strip: its 14-bit pair and the note held while it's touched.
    private mutating func needle(_ capture: CaptureFile) {
        let key = "mapping.needle"
        guard let controls = controls(capture, "deck1.needle", for: key) else { return }
        guard let strip = controls.first(where: { $0.kind == .cc }), let msb = strip.number, let lsb = strip.lsb else {
            todo(key, "The needle strip didn't send a 14-bit CC pair. Check it in MIDI Monitor; profiles need msb_cc and lsb_cc.")
            return
        }
        set("\(key).msb_cc", .int(msb))
        set("\(key).lsb_cc", .int(lsb))
        if let touch = controls.first(where: { $0.kind == .note })?.number {
            set("\(key).touch_note", .int(touch))
        } else {
            todo("\(key).touch_note", "No note came while the strip was touched. If it has no touch sensor, needle.require_touch must be false.")
        }
    }

    /// The browse knob's CC, and from its turn the relative encoder format (#193) unless the jog already set it.
    private mutating func browse(_ capture: CaptureFile) {
        guard let control = control(capture, "deck1.browse.turn", for: "mapping.browse.select_turn_cc") else { return }
        guard control.kind == .cc, let number = control.number else {
            todo("mapping.browse.select_turn_cc", "The browse knob didn't send a CC. Check it in MIDI Monitor.")
            return
        }
        set("mapping.browse.select_turn_cc", .int(number))
        encoderFormat(control.encoding, from: "deck1.browse.turn")
    }

    /// The profile's one relative encoder format. A turn that couldn't tell (one way only) or an absolute knob is a TODO.
    mutating func encoderFormat(_ encoding: ControlEncoding?, from prompt: String) {
        let key = "mapping.midi.encoder_format"
        switch encoding {
        case .twosComplement, .offset64, .signMagnitude:
            todos.removeAll { $0.key == key }
            if profile.value(at: key) == nil { set(key, .string(encoding!.rawValue)) }
        case .absolute:
            todo(key, "\"\(prompt)\" sent absolute values, not relative steps. Check whether it's an endless encoder.")
        case nil:
            if profile.value(at: key) == nil {
                todo(key, "\"\(prompt)\" turned only one way, so its format can't be told. Run it again, right then left.")
            }
        }
    }

    /// Notes that came in with hands off (a heartbeat) are ignored, so they never press anything.
    private mutating func noise(_ capture: CaptureFile) {
        let notes = capture.noise.compactMap { key -> Int? in
            key.count == 2 && key[0] & 0xF0 == 0x90 ? Int(key[1]) : nil
        }
        set("mapping.midi.ignore_notes", .array(notes.map(DraftJSON.int)))
    }

    /// Lowercase letters and digits, runs of anything else as one hyphen.
    static func slug(_ name: String) -> String {
        name.lowercased().split { !($0.isLetter || $0.isNumber) || !$0.isASCII }.joined(separator: "-")
    }
}
