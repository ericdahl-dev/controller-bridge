/// The Diagnostics window's tabs, in Syndicate-style words (#70).
public enum DiagnosticsTab: String, CaseIterable, Sendable {
    case monitor = "MIDI Monitor"
    case sweep = "LED Sweep"
    case osc = "OSC Log"

    /// The line shown in an empty list, so "nothing yet" never looks like "broken".
    public func emptyText(controllerConnected: Bool) -> String {
        switch self {
        case .monitor: controllerConnected ? "Press any button on the controller." : "No controller connected."
        case .sweep: "Press Start Sweep. Watch the pads and ring."
        case .osc: "Nothing sent or received yet."
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
    private var nextID = 0

    public init() {}

    public mutating func append(to tab: DiagnosticsTab, message: String, label: String = "", isUnmapped: Bool = false) {
        nextID += 1
        var list = lists[tab, default: []]
        list.append(Line(id: nextID, message: message, label: label, isUnmapped: isUnmapped))
        if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
        lists[tab] = list
    }

    /// Empties one tab's list; the others stay.
    public mutating func clear(_ tab: DiagnosticsTab) {
        lists[tab] = []
    }

    /// What a tab shows, oldest first.
    public func shown(_ tab: DiagnosticsTab) -> [Line] {
        let list = lists[tab, default: []]
        guard tab == .osc, hideProgressAndTime else { return list }
        return list.filter { !Self.isProgressOrTime($0.text) }
    }

    /// "OSC <- /Syndicate/Deck/1/Progress 0.25" or ".../Time 61": the address's last part, before the arguments.
    private static func isProgressOrTime(_ text: String) -> Bool {
        guard text.hasPrefix("OSC <- ") else { return false }
        let address = text.dropFirst(7).split(separator: " ").first ?? ""
        let last = address.split(separator: "/").last?.lowercased()
        return last == "progress" || last == "time"
    }
}
