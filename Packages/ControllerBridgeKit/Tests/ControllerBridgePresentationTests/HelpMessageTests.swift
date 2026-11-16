import ControllerBridgePresentation
import Testing

/// Why the LEDs are dark, in plain words, with a link to the setup guide (#27). One message at a time, most urgent first.
@Suite("Help message")
struct HelpMessageTests {
    static func state(_ feedback: BridgeState.Feedback,
                      _ controller: BridgeState.Controller = .connected(profile: "Denon LC6000 PRIME")) -> BridgeState {
        BridgeState(controller: controller, feedback: feedback, deck: 1)
    }

    @Test("Port in use: says another app has the port, so feedback can't arrive, and links the guide")
    func portInUse() {
        #expect(HelpMessage(Self.state(.portInUse(port: 9096))) == HelpMessage(
            text: "Another app is using port 9096, so Syndicate's feedback can't reach the bridge and the LEDs stay dark. Quit the other app, such as a second bridge, then reopen this one.",
            showsGuide: true
        ))
    }

    @Test("No feedback yet: names Syndicate's OSC FEEDBACK settings to check, and links the guide")
    func waiting() {
        #expect(HelpMessage(Self.state(.waiting(port: 9096))) == HelpMessage(
            text: "Syndicate hasn't sent any feedback yet, so the LEDs stay dark. In Syndicate's Settings → OSC FEEDBACK, set DEST IP to 127.0.0.1 and PORT to 9096.",
            showsGuide: true
        ))
    }

    @Test("Feedback dropped: asks whether Syndicate is still running, and links the guide")
    func dropped() {
        #expect(HelpMessage(Self.state(.stopped(port: 9096))) == HelpMessage(
            text: "Syndicate's feedback stopped, so the LEDs may be out of date. Is Syndicate still running? When it answers again, the bridge asks it to RESEND STATE.",
            showsGuide: true
        ))
    }

    @Test("No controller, feedback live: says to plug it in; the guide isn't the fix, so no link")
    func noController() {
        #expect(HelpMessage(Self.state(.live(port: 9096), .notConnected)) == HelpMessage(
            text: "No controller is connected. Plug it in over USB, and the bridge connects to it by itself.",
            showsGuide: false
        ))
    }

    @Test("All well: no message")
    func allWell() {
        #expect(HelpMessage(Self.state(.live(port: 9096))) == nil)
    }

    @Test("Feedback problems come before a missing controller: the port message wins")
    func feedbackFirst() {
        #expect(HelpMessage(Self.state(.portInUse(port: 9096), .notConnected))?.text.hasPrefix("Another app is using port 9096") == true)
    }
}
