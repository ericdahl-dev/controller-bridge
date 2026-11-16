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
public struct DiagnosticsLines: Equatable, Sendable {
    public static let limit = 500

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
    private var lists: [DiagnosticsTab: [Line]] = [:]
    /// The OSC tab's Progress and Time lines, kept apart so their flood can't push the other lines out (#97).
    private var progressAndTime: [Line] = []
    private var nextID = 0

    public init() {}

    public mutating func append(to tab: DiagnosticsTab, message: String, label: String = "", isUnmapped: Bool = false) {
        nextID += 1
        let line = Line(id: nextID, message: message, label: label, isUnmapped: isUnmapped)
        if tab == .osc, Self.isProgressOrTime(line.text) {
            progressAndTime.append(line)
            if progressAndTime.count > Self.limit { progressAndTime.removeFirst(progressAndTime.count - Self.limit) }
            return
        }
        var list = lists[tab, default: []]
        list.append(line)
        if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
        lists[tab] = list
    }

    /// Empties one tab's list; the others stay.
    public mutating func clear(_ tab: DiagnosticsTab) {
        lists[tab] = []
        if tab == .osc { progressAndTime = [] }
    }

    /// What a tab shows, oldest first.
    public func shown(_ tab: DiagnosticsTab) -> [Line] {
        let list = lists[tab, default: []]
        guard tab == .osc, !hideProgressAndTime else { return list }
        // Both kept lists, back in arrival order, and still no more than the limit.
        return Array((list + progressAndTime).sorted { $0.id < $1.id }.suffix(Self.limit))
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
