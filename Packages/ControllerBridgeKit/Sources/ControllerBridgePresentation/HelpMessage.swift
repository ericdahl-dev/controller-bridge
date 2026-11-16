/// Why the LEDs are dark, in plain words, for the panel (#27). One message at a time, most urgent first; nil when
/// nothing needs explaining.
public struct HelpMessage: Equatable, Sendable {
    public var text: String
    /// Whether the panel links the setup guide next to it.
    public var showsGuide: Bool

    public init(text: String, showsGuide: Bool) {
        self.text = text
        self.showsGuide = showsGuide
    }

    public init?(_ state: BridgeState) {
        switch state.feedback {
        case .portInUse(let port):
            self.init(
                text: "Another app is using port \(port), so Syndicate's feedback can't reach the bridge and the LEDs stay dark. Quit the other app, such as a second bridge, then reopen this one.",
                showsGuide: true
            )
        case .waiting(let port):
            self.init(
                text: "Syndicate hasn't sent any feedback yet, so the LEDs stay dark. In Syndicate's Settings → OSC FEEDBACK, set DEST IP to 127.0.0.1 and PORT to \(port).",
                showsGuide: true
            )
        case .stopped:
            self.init(
                text: "Syndicate's feedback stopped, so the LEDs may be out of date. Is Syndicate still running? When it answers again, the bridge asks it to RESEND STATE.",
                showsGuide: true
            )
        case .starting, .live, .failed:
            // A failed listener shows its reason in the panel already.
            guard state.controller == .notConnected else { return nil }
            self.init(text: "No controller is connected. Plug it in over USB, and the bridge connects to it by itself.", showsGuide: false)
        }
    }
}
