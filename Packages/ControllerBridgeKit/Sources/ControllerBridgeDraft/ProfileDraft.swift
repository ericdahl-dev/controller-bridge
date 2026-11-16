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

    /// Lowercase letters and digits, runs of anything else as one hyphen.
    static func slug(_ name: String) -> String {
        name.lowercased().split { !($0.isLetter || $0.isNumber) || !$0.isASCII }.joined(separator: "-")
    }
}
