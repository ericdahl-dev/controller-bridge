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
        // A bridge that couldn't start comes first. The raw error is for Diagnostics, not the panel (#66).
        if state.stopped {
            self.init(text: "The bridge couldn't open MIDI. Quit and reopen it. If that doesn't help, restart the Mac.", showsGuide: false)
            return
        }
        // Two short lines each (#66).
        switch state.feedback {
        case .portInUse(let port):
            self.init(text: "Another app holds port \(port). Quit it, then reopen the bridge.", showsGuide: true)
        case .waiting(let port):
            self.init(text: "No feedback from Syndicate yet. Set OSC FEEDBACK to 127.0.0.1 : \(port).", showsGuide: true)
        case .stopped:
            self.init(text: "Syndicate stopped answering. Is it still running? The LEDs catch up when it's back.", showsGuide: true)
        case .starting, .live, .failed:
            // A failed listener shows its reason in the panel already.
            switch state.controller {
            case .notConnected:
                self.init(text: "No controller connected. Plug it in over USB; the bridge finds it.", showsGuide: false)
            case .unplugged:
                self.init(text: "The controller was unplugged. Plug it back in; the bridge picks it up again.", showsGuide: false)
            case .failed:
                self.init(text: "Lost contact with the controller. Check the USB cable, then unplug and replug.", showsGuide: false)
            case .waiting:
                self.init(text: "Waiting for the device chosen in Settings.", showsGuide: false)
            case .connected:
                return nil
            }
        }
    }
}
