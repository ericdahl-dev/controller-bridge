/// The MIDI sources no controller profile matches (#43), as the panel lists them.
public struct OtherDevices: Equatable, Sendable {
    /// An orange NO PROFILE row, shown on its own.
    public var highlighted: StatusLight?
    /// The quiet gray line the rest collapse under, such as "OTHER MIDI DEVICES (2)". Nil when there are none.
    public var summary: String?
    /// The expanded rows, in gray.
    public var rows: [String]

    public init(unmatched: [String], controllerConnected: Bool) {
        var rest = unmatched
        // With no controller connected, an unmatched device is probably the user's controller: call it out.
        highlighted = !controllerConnected && !rest.isEmpty ? StatusLight(unmatchedDevice: rest.removeFirst()) : nil
        summary = rest.isEmpty ? nil : "OTHER MIDI DEVICES (\(rest.count))"
        rows = rest.map { "\($0) · no profile" }
    }
}
