/// The MIDI sources no controller profile matches (#43), as the panel lists them.
public struct OtherDevices: Equatable, Sendable {
    /// An orange NO PROFILE row, shown on its own.
    public var highlighted: StatusLight?
    /// For the highlighted device, the way to help add it (#200).
    public var offer: CaptureOffer?
    /// The quiet gray line the rest collapse under, such as "Other MIDI devices (2)", natural case: the view uppercases it. Nil when there are none.
    public var summary: String?
    /// The expanded rows, in gray.
    public var rows: [String]

    /// `ownPorts` are a known controller's other ports, such as the LC6000's WD port: listed, never offered.
    public init(unmatched: [String], ownPorts: [(name: String, of: String)] = [], controllerConnected: Bool) {
        var rest = unmatched
        // With no controller connected, an unmatched device is probably the user's controller: call it out. macOS's own
        // virtual ports never are.
        let candidate = controllerConnected ? nil : rest.firstIndex { !Self.isVirtual($0) }
        if let candidate {
            let name = rest.remove(at: candidate)
            highlighted = StatusLight(unmatchedDevice: name)
            offer = CaptureOffer(device: name, text: "\(name) isn't supported yet.", action: "Help add it…")
        }
        rows = rest.map { "\($0) · no profile" } + ownPorts.map { "\($0.name) · part of the \($0.of)" }
        summary = rows.isEmpty ? nil : "Other MIDI devices (\(rows.count))"
    }

    /// The IAC Driver's buses and network MIDI sessions: ports macOS makes, not controllers.
    static func isVirtual(_ name: String) -> Bool {
        name.hasPrefix("IAC ") || name.hasPrefix("Network Session")
    }
}

/// The panel's offer for a controller DeckBridge doesn't support yet (#200): it opens the capture window.
public struct CaptureOffer: Equatable, Sendable {
    /// The device to capture, preselected in the window.
    public var device: String
    public var text: String
    /// The button's title.
    public var action: String

    public init(device: String, text: String, action: String) {
        self.device = device
        self.text = text
        self.action = action
    }
}
