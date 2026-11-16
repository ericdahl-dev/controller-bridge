import ControllerBridgeCore

/// The Settings window's tabs (#171), in toolbar order. ⌘1–4 pick them.
public enum SettingsTab: Int, CaseIterable, Hashable, Sendable {
    case controller = 1, decks, syndicate, general

    public var title: String {
        switch self {
        case .controller: "Controller"
        case .decks: "Decks"
        case .syndicate: "Syndicate"
        case .general: "General"
        }
    }

    /// The key that picks this tab with ⌘.
    public var shortcut: Character { Character(String(rawValue)) }

    /// The tab a field shows on.
    public init(field: SettingsField) {
        switch field {
        case .deck, .channel, .device: self = .controller
        case .deckColor: self = .decks
        case .host, .oscPort, .feedbackPort: self = .syndicate
        }
    }
}

/// What a refused Apply does in the tabbed window (#171): go to the leftmost tab with a problem and focus its first
/// bad field. A problem with no field, such as the bridge not running, leaves the tab alone.
public struct SettingsRefusal: Equatable, Sendable {
    public var tab: SettingsTab?
    public var focus: SettingsField?

    public init(fields: [SettingsProblem], other: [String] = []) {
        let first = fields.min { SettingsTab(field: $0.field).rawValue < SettingsTab(field: $1.field).rawValue }
        tab = first.map { SettingsTab(field: $0.field) }
        focus = first?.field
    }
}
