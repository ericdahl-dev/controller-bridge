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
        guard let step = capture.steps.first(where: { $0.prompt == prompt }) else {
            todo(key, "The capture has no \"\(prompt)\" step. Run the capture again with the current prompt list.")
            return nil
        }
        guard step.status == .confirmed else {
            todo(key, "The owner skipped \"\(prompt)\". Ask them to run that step again, or read it from the docs.")
            return nil
        }
        guard let control = step.controls.first else {
            todo(key, "\"\(prompt)\" was confirmed but found no control (only noise came in). Run that step again.")
            return nil
        }
        return control
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
