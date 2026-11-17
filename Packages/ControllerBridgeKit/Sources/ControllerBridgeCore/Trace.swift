import Foundation

/// The debug trace (#395): what a Debug build writes to os_log and to a rolling file, so an agent can read what the
/// controller, Syndicate and the jog display did without asking the user for a paste. Release builds never set it.
public enum TraceCategory: String, CaseIterable, Sendable {
    case midiIn = "midi-in"
    case midiOut = "midi-out"
    case oscIn = "osc-in"
    case oscOut = "osc-out"
    case jogDisplay = "jog-display"
    case coordinator
    case capture
    case quantize
    case subscriptions
    case error
}

/// Where trace lines go: `(category, text)`. Nil (Release, tests that don't look) costs nothing.
public typealias TraceSink = @Sendable (TraceCategory, String) -> Void

public enum TraceLine {
    /// "2025-11-16T22:41:03.123Z osc-in        /Syndicate/Deck/1/Playing 1": UTC to the millisecond, the category
    /// padded to the longest (13), the text. One line, so `grep` and `tail` work on the file.
    public static func format(at date: Date, _ category: TraceCategory, _ text: String) -> String {
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                        from: Date(timeIntervalSince1970: Double(millis / 1000)))
        let stamp = String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0, Int(millis % 1000))
        let name = category.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
        return "\(stamp) \(name) \(text.replacingOccurrences(of: "\n", with: " "))"
    }
}
