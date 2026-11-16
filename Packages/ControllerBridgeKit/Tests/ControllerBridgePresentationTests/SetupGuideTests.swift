import ControllerBridgePresentation
import Foundation
import Testing

/// The first-run guide's steps, in Syndicate's own setting names (#27). Generic: the controller is named by its profile.
@Suite("Setup guide")
struct SetupGuideTests {
    @Test("Four steps in Syndicate's words: OSC input, feedback destination, subscriptions, and the controller's MIDI input off")
    func steps() {
        let guide = SetupGuide(controller: "Denon LC6000 PRIME", oscPort: 9090, feedbackPort: 9096)
        #expect(guide.steps.map(\.title) == [
            "Settings → OSC",
            "Settings → OSC FEEDBACK",
            "Subscriptions",
            "Settings → MIDI",
        ])
        #expect(guide.steps.map(\.detail) == [
            "Turn OSC INPUT ENABLED on. The listen port is 9090.",
            "Set DEST IP to 127.0.0.1 and PORT to 9096.",
            "Tick Playing, PlayPending, Loaded and TrackInfo, Position/Progress, TempoSlider/TempoSliderEnabled, Cues, BPM/Sync and Loop.",
            "Turn Denon LC6000 PRIME's MIDI input off. Otherwise Syndicate's own mapping and the bridge would both react to every button.",
        ])
    }

    @Test("With no profile yet, the MIDI step says \"your controller\" and names no device")
    func genericController() {
        let guide = SetupGuide(controller: nil, oscPort: 9090, feedbackPort: 9096)
        #expect(guide.steps.last?.detail.hasPrefix("Turn your controller's MIDI input off.") == true)
    }

    @Test("The README's \"Set up Syndicate\" section lists the same subscriptions and says the same about the MIDI input")
    func matchesTheReadme() throws {
        // Tests/ControllerBridgePresentationTests/ → repo root.
        let readme = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../README.md")
        let text = try String(contentsOf: readme, encoding: .utf8)
        let subscriptions = SetupGuide.subscriptions.dropLast().joined(separator: ", ") + " and " + SetupGuide.subscriptions.last!
        #expect(text.contains("Tick these subscriptions: \(subscriptions)."))
        #expect(text.contains("turn your controller's MIDI input **off**"))
    }

    @Test("The guide opens on first launch and again when its content changes, but not on every launch")
    func firstRun() {
        #expect(SetupGuide.shouldShowAtLaunch(seenVersion: nil))
        #expect(!SetupGuide.shouldShowAtLaunch(seenVersion: SetupGuide.version))
        #expect(SetupGuide.shouldShowAtLaunch(seenVersion: SetupGuide.version - 1))
    }
}
