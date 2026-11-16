import Foundation

// What the owner sees before saving or emailing a capture (#188).

extension CaptureFile {
    /// Everything the file holds, in plain words, ending with what it doesn't.
    public var summary: [String] {
        let captured = steps.filter { $0.status == .confirmed }.count
        let messages = steps.reduce(0) { $0 + $1.messages.count }
        let leds = steps.reduce(0) { $0 + $1.leds.count }
        var lines = [
            "Controller: \(device)",
            "Ports: \(ports.input.joined(separator: ", ")) (in)" + (ports.output.isEmpty ? "" : "; \(ports.output.joined(separator: ", ")) (out)"),
            "\(Self.count(steps.count, "step")): \(captured) captured, \(steps.count - captured) skipped",
            "\(Self.count(messages, "MIDI message")), as the controller sent \(messages == 1 ? "it" : "them")",
        ]
        if leds > 0 { lines.append(Self.count(leds, "LED answer")) }
        lines.append(note.map { "Your note: \($0)" } ?? "No note")
        lines.append("DeckBridge \(appVersion)")
        lines.append("Nothing else: no name, email, location or time of day.")
        return lines
    }

    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

extension CaptureFile {
    /// The capture file's extension, as the app's exported type declares it.
    public static let fileExtension = "deckbridge-capture"
    public static let emailRecipient = "deckbridge@ericdahl.dev"

    /// "LC6000 PRIME capture.deckbridge-capture", with / and : (which a file name can't hold) made hyphens.
    public var suggestedFileName: String {
        let name = device.trimmingCharacters(in: .whitespaces).map { $0 == "/" || $0 == ":" ? "-" : String($0) }.joined()
        return "\(name.isEmpty ? "Controller" : name) capture.\(Self.fileExtension)"
    }

    public var emailSubject: String { "Controller capture: \(device)" }
    public var emailBody: String { "Here's a capture of my \(device) for DeckBridge. The file is attached." }
}
