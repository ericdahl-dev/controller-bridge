/// Settings › Controller's Controller picker (#200): Automatic (match by device name) or a profile chosen by hand,
/// saved for the card's device. Its last item, Controller not found?, opens the capture window (#186).
public struct ProfilePicker: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Hashable {
        /// The profile's id; nil is Automatic.
        public var id: String?
        public var title: String

        public init(id: String?, title: String) {
            self.id = id
            self.title = title
        }
    }

    public static let notFoundTitle = "Controller not found?"

    /// The device a choice is saved for: the card's chosen input, else the device it runs on, else the unsupported
    /// device the panel highlights. Nil when there's none.
    public var device: String?
    public var options: [Option]
    /// The device's saved profile id, or nil for Automatic (also when the saved profile is gone).
    public var selected: String?
    public var enabled: Bool { device != nil }
    public var hint: String

    public init(
        chosenInput: String?, connectedDevice: String?, unsupported: String?, profiles: [(id: String, name: String)],
        choices: [String: String]
    ) {
        device = chosenInput ?? connectedDevice ?? unsupported
        options = [Option(id: nil, title: "Automatic (match by device name)")] + profiles.map { Option(id: $0.id, title: $0.name) }
        let saved = device.flatMap { choices[$0] }
        selected = profiles.contains { $0.id == saved } ? saved : nil
        hint = device.map { "For \($0)" } ?? "Connect your controller to choose its profile"
    }
}
