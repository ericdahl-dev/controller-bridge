/// The Diagnostics window's tabs, in Syndicate-style words (#70).
public enum DiagnosticsTab: String, CaseIterable, Sendable {
    case monitor = "MIDI Monitor"
    case sweep = "LED Sweep"
    case osc = "OSC Log"

    /// The line shown in an empty list, so "nothing yet" never looks like "broken".
    /// What Save… suggests (#162), such as "DeckBridge OSC Log.txt". The app passes its display name.
    public func exportFileName(appName: String) -> String {
        "\(appName) \(rawValue).txt"
    }

    public func emptyText(controllerConnected: Bool) -> String {
        switch self {
        case .monitor: controllerConnected ? "Press any button on the controller." : "No controller connected."
        case .sweep: "Press Start Sweep. Watch the pads and ring."
        case .osc: "Nothing sent or received yet."
        }
    }

    /// The monitor's note about the notes the profile ignores (#103), so a quiet monitor doesn't look like a dead port.
    public static func hiddenNotesHint(_ notes: [Int]) -> String? {
        switch notes.count {
        case 0: nil
        case 1: "Note \(notes[0]), the controller's idle heartbeat, is hidden."
        default:
            "Notes " + notes.dropLast().map(String.init).joined(separator: ", ") + " and \(notes.last!), which the controller "
                + "sends on its own, are hidden."
        }
    }
}

/// Whether Start Sweep can run, and if not, why: the sweep lights the controller, so it needs its LED output.
public struct SweepAvailability: Equatable, Sendable {
    public var enabled: Bool
    public var reason: String?

    public init(enabled: Bool, reason: String?) {
        self.enabled = enabled
        self.reason = reason
    }

    public init(outputOpen: Bool) {
        self.init(enabled: outputOpen, reason: outputOpen ? nil : "No controller output. Plug in the controller.")
    }
}

/// The three Diagnostics lists. Each keeps its newest lines only, so a long set doesn't grow without bound.
/// Memory (#218): at most `limit` lines per list, plus `limit` streaming lines for the OSC log. A line is about 100 bytes
/// of text plus its fields, so a full OSC log holds roughly 2 × 20,000 × ~150 B ≈ 6 MB, and the three tabs under 15 MB.
public struct DiagnosticsLines: Equatable, Sendable {
    public static let limit = 20_000

    /// One line: the message, and for the monitor its mapping label, which the window colors when it's UNMAPPED.
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: Int
        public let message: String
        public let label: String
        public let isUnmapped: Bool
        /// The line exactly as the Python bridge printed it.
        public var text: String { message + label }
    }

    /// Progress and Time feedback arrive many times a second while playing; hidden by default.
    public var hideProgressAndTime = true
    private var lists: [DiagnosticsTab: Ring] = [:]
    /// The OSC tab's Progress and Time lines, kept apart so their flood can't push the other lines out (#97).
    private var progressAndTime = Ring()
    private var nextID = 0

    public init() {}

    public mutating func append(to tab: DiagnosticsTab, message: String, label: String = "", isUnmapped: Bool = false) {
        nextID += 1
        let line = Line(id: nextID, message: message, label: label, isUnmapped: isUnmapped)
        if tab == .osc, Self.isProgressOrTime(line.text) {
            progressAndTime.append(line)
            return
        }
        lists[tab, default: Ring()].append(line)
    }

    /// Empties one tab's list; the others stay.
    public mutating func clear(_ tab: DiagnosticsTab) {
        lists[tab] = Ring()
        if tab == .osc { progressAndTime = Ring() }
    }

    /// What a tab shows, oldest first.
    public func shown(_ tab: DiagnosticsTab) -> [Line] {
        let list = lists[tab, default: Ring()].lines
        guard tab == .osc, !hideProgressAndTime else { return list }
        // Both kept lists, back in arrival order, and still no more than the limit.
        return Array(Self.merged(list, progressAndTime.lines).suffix(Self.limit))
    }

    /// Two lists already in arrival order, merged into one in arrival order, in one pass.
    private static func merged(_ a: [Line], _ b: [Line]) -> [Line] {
        var out: [Line] = []
        out.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i].id < b[j].id { out.append(a[i]); i += 1 } else { out.append(b[j]); j += 1 }
        }
        out += a[i...]
        out += b[j...]
        return out
    }

    /// The newest `limit` lines in a fixed array, overwriting the oldest: appending costs the same at 20,000 as at 1.
    struct Ring: Equatable, Sendable {
        private var storage: [Line] = []
        private var start = 0

        mutating func append(_ line: Line) {
            if storage.count < DiagnosticsLines.limit {
                storage.append(line)
            } else {
                storage[start] = line
                start = (start + 1) % storage.count
            }
        }

        /// Oldest first.
        var lines: [Line] { start == 0 ? storage : Array(storage[start...] + storage[..<start]) }

        static func == (a: Ring, b: Ring) -> Bool { a.lines == b.lines }
    }

    /// What a tab shows, as plain text to copy or save (#162): one line each, ending in a newline. UNMAPPED keeps its
    /// words; the dot is only how the window draws it.
    public func plainText(_ tab: DiagnosticsTab) -> String {
        shown(tab).map { $0.text + "\n" }.joined()
    }

    /// "OSC <- /Syndicate/Deck/1/Progress 0.25" or ".../Time 61": the address's last part, before the arguments.
    private static func isProgressOrTime(_ text: String) -> Bool {
        guard text.hasPrefix("OSC <- ") else { return false }
        let address = text.dropFirst(7).split(separator: " ").first ?? ""
        let last = address.split(separator: "/").last?.lowercased()
        return last == "progress" || last == "time"
    }
}
