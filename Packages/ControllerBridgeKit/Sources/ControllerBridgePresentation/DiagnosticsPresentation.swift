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
