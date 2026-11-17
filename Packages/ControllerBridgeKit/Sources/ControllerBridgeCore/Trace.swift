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

/// Keeps the trace readable (#395): Syndicate streams some feedback (Position ~100/s per deck, BarRamp ~200/s, Meter
/// ~100/s per channel, #209), so each such address is kept at most `perSecond` times a second, and the next line kept
/// says how many were skipped. Every other message is kept.
public struct StreamSampler: Sendable {
    /// The streaming feedback, by the address's last part, as Diagnostics' streaming filter (#218).
    public static let streamingNames: Set<String> = ["position", "barramp", "meter", "clock", "currentstep", "sampleprogress",
                                                     "progress", "time"]
    public let perSecond: Double
    private var last: [String: Double] = [:]
    private var skipped: [String: Int] = [:]

    public init(perSecond: Double = 5) {
        self.perSecond = perSecond
    }

    /// Nil to skip this message; otherwise what to append to its line: "" or " (+N skipped)".
    public mutating func admit(_ address: String, at now: Double) -> String? {
        let name = address.split(separator: "/").last.map { $0.lowercased() } ?? ""
        guard Self.streamingNames.contains(name) else { return "" }
        if let previous = last[address], now - previous < 1 / perSecond - 1e-9 {
            skipped[address, default: 0] += 1
            return nil
        }
        last[address] = now
        let count = skipped.removeValue(forKey: address) ?? 0
        return count > 0 ? " (+\(count) skipped)" : ""
    }
}
