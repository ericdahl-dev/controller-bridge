/// The first-run guide (#27): what to set in Syndicate, in Syndicate's own setting names. It matches the README's
/// "Set up Syndicate" section; a test keeps the subscription list in step with it.
public struct SetupGuide: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var title: String
        public var detail: String
    }

    /// The feedback Syndicate must send, as its OSC FEEDBACK subscriptions are named.
    public static let subscriptions = [
        "Playing", "PlayPending", "Loaded and TrackInfo", "Position/Progress", "TempoSlider/TempoSliderEnabled", "Cues",
        "BPM/Sync", "Loop",
    ]

    public var steps: [Step]

    /// `controller` is the profile's name, such as "Denon LC6000 PRIME", or nil when there is none yet.
    public init(controller: String?, oscPort: Int, feedbackPort: Int) {
        let list = Self.subscriptions.dropLast().joined(separator: ", ") + " and " + Self.subscriptions.last!
        let device = controller.map { "\($0)'s" } ?? "your controller's"
        steps = [
            Step(title: "Settings → OSC", detail: "Turn OSC INPUT ENABLED on. The listen port is \(oscPort)."),
            Step(title: "Settings → OSC FEEDBACK", detail: "Set DEST IP to 127.0.0.1 and PORT to \(feedbackPort)."),
            Step(title: "Subscriptions", detail: "Tick \(list)."),
            Step(title: "Settings → MIDI",
                 detail: "Turn \(device) MIDI input off. Otherwise Syndicate's own mapping and the bridge would both react to every button."),
        ]
    }
}
