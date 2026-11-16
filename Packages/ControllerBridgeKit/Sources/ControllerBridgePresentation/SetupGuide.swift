/// The first-run guide (#27): what to set in Syndicate, in Syndicate's own setting names. It matches the README's
/// "Set up Syndicate" section; a test keeps the subscription list in step with it.
public struct SetupGuide: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var title: String
        public var detail: String
        /// Items to turn on, shown as a checklist under the detail (#68).
        public var checklist: [String] = []
    }

    /// The guide's closing line.
    public static let footer = "On start, the bridge asks Syndicate to RESEND STATE, so the LEDs light at once."

    /// The Done button's label: it confirms the setup once feedback is live (#68). Natural case; the button uppercases.
    public static func doneTitle(feedbackLive: Bool) -> String {
        feedbackLive ? "Done: feedback live" : "Done"
    }

    /// The feedback Syndicate must send, as its OSC FEEDBACK subscriptions are named.
    public static let subscriptions = [
        "Playing", "PlayPending", "Loaded and TrackInfo", "Position/Progress", "TempoSlider/TempoSliderEnabled", "Cues",
        "BPM/Sync", "Loop",
    ]

    /// Bump when the steps change in a way a returning user should see.
    public static let version = 1

    /// Whether to open the guide at launch, given the last version this Mac saw (nil: never).
    public static func shouldShowAtLaunch(seenVersion: Int?) -> Bool {
        (seenVersion ?? 0) < version
    }

    public var steps: [Step]

    /// `controller` is the profile's name, such as "Denon LC6000 PRIME", or nil when there is none yet.
    public init(controller: String?, oscPort: Int, feedbackPort: Int) {
        let device = controller.map { "\($0)'s" } ?? "your controller's"
        steps = [
            Step(title: "Settings → OSC", detail: "Turn OSC INPUT ENABLED on. The listen port is \(oscPort)."),
            Step(title: "Settings → OSC FEEDBACK", detail: "Set DEST IP to 127.0.0.1 and PORT to \(feedbackPort)."),
            // All four titles follow Syndicate's menu path (#68).
            Step(title: "Settings → OSC FEEDBACK → SUBSCRIPTIONS", detail: "Turn on these OSC FEEDBACK subscriptions:",
                 checklist: Self.subscriptions),
            Step(title: "Settings → MIDI",
                 detail: "Turn \(device) MIDI input off. Otherwise Syndicate's own mapping and the bridge would both react to every button."),
        ]
    }
}
