/// Quitting from the panel (#131). While feedback is live, Quit asks first, inside the panel: a dialog attached to a
/// menu-bar window may never show, which left Quit doing nothing. Every path ends in a quit or back to idle.
public struct QuitFlow: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case quitNow
    }

    public static let question = "Quit? The controller stops sending to Syndicate."

    /// The question is showing in the panel.
    public private(set) var confirming = false

    public init() {}

    /// The Quit button. `asks` is `StatusPresentation.quitAsks`. Once asked, pressing Quit again quits.
    public mutating func pressQuit(asks: Bool) -> Action? {
        if confirming || !asks { return confirm() }
        confirming = true
        return nil
    }

    /// Quit, from the question.
    public mutating func confirm() -> Action {
        confirming = false
        return .quitNow
    }

    public mutating func cancel() { confirming = false }

    /// The panel closed: the question goes away with it.
    public mutating func panelClosed() { confirming = false }
}
