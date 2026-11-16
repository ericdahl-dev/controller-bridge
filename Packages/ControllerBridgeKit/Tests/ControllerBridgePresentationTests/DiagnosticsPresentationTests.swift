import ControllerBridgePresentation
import Testing

/// The Diagnostics window's words and lists (#70), apart from the SwiftUI.
@Suite("Diagnostics presentation")
struct DiagnosticsPresentationTests {
    @Test("Each empty list says what to do; the monitor's line depends on whether a controller is connected")
    func emptyStates() {
        #expect(DiagnosticsTab.monitor.emptyText(controllerConnected: true) == "Press any button on the controller.")
        #expect(DiagnosticsTab.monitor.emptyText(controllerConnected: false) == "No controller connected.")
        #expect(DiagnosticsTab.sweep.emptyText(controllerConnected: true) == "Press Start Sweep. Watch the pads and ring.")
        #expect(DiagnosticsTab.osc.emptyText(controllerConnected: false) == "Nothing sent or received yet.")
    }

    @Test("Start Sweep needs the controller's LED output: without one it's disabled, with the reason")
    func sweepAvailability() {
        #expect(SweepAvailability(outputOpen: true) == SweepAvailability(enabled: true, reason: nil))
        #expect(SweepAvailability(outputOpen: false) == SweepAvailability(enabled: false, reason: "No controller output. Plug in the controller."))
    }

    @Test("Clear empties only the tab you're on")
    func clearOneTab() {
        var lines = DiagnosticsLines()
        lines.append(to: .monitor, message: "       1.500  ch1  note_on channel=0 note=1 velocity=127 time=0", label: "play")
        lines.append(to: .osc, message: "OSC -> /Syndicate/Deck/1/PlayPause 1")
        lines.append(to: .sweep, message: "pads+ring velocity 0x00 (0)")
        lines.clear(.osc)
        #expect(lines.shown(.osc).isEmpty)
        #expect(lines.shown(.monitor).map(\.label) == ["play"])
        #expect(lines.shown(.sweep).count == 1)
    }

    @Test("Each list keeps its newest 20,000 lines (#218): about a minute of busy feedback, not one second")
    func limit() {
        var lines = DiagnosticsLines()
        for n in 1...20_001 { lines.append(to: .osc, message: "OSC -> /Syndicate/Browser/Down \(n)") }
        let shown = lines.shown(.osc)
        #expect(shown.count == 20_000)
        #expect(shown.first?.message == "OSC -> /Syndicate/Browser/Down 2")
        #expect(shown.last?.message == "OSC -> /Syndicate/Browser/Down 20001")
    }

    @Test("Hide streaming values (#218) hides Syndicate's fast feedback: Position, BarRamp, Meter, Header/Clock, CurrentStep, SampleProgress, Progress and Time")
    func hideStreaming() {
        var lines = DiagnosticsLines()
        for message in [
            "OSC <- /Syndicate/Deck/3/Position 48.91",
            "OSC <- /Syndicate/Deck/3/BarRamp 0.42",
            "OSC <- /Syndicate/Mixer/CH3/Meter 0.61",
            "OSC <- /Syndicate/Header/Clock 2",
            "OSC <- /Syndicate/Deck/1/CurrentStep 5",
            "OSC <- /Syndicate/Deck/1/SampleProgress 0.5",
            "OSC <- /Syndicate/Deck/1/Progress 0.25",
            "OSC <- /Syndicate/Deck/1/Time 61",
            "OSC <- /Syndicate/Header/BPM 128.0",
            "OSC <- /Syndicate/Deck/3/TrackInfo \"Song\" \"Artist\"",
            "OSC -> /Syndicate/Deck/3/Position 0.5",
        ] { lines.append(to: .osc, message: message) }
        #expect(lines.hideStreaming)
        #expect(lines.shown(.osc).map(\.message) == [
            "OSC <- /Syndicate/Header/BPM 128.0",
            "OSC <- /Syndicate/Deck/3/TrackInfo \"Song\" \"Artist\"",
            "OSC -> /Syndicate/Deck/3/Position 0.5",
        ])
        lines.hideStreaming = false
        #expect(lines.shown(.osc).count == 11)
    }

    @Test("Hidden streaming lines can't push the rest out: after 20,100 of them, the Playing line is still shown (#97)")
    func hiddenLinesDontEvict() {
        var lines = DiagnosticsLines()
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Playing 1")
        for n in 1...20_100 { lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Progress 0.\(n)") }
        #expect(lines.shown(.osc).map(\.message) == ["OSC <- /Syndicate/Deck/1/Playing 1"])

        // Unticking the box shows everything in arrival order, newest 20,000: the Progress list kept its newest 20,000
        // (0.101 to 0.20100), and with Playing that is 20,001 lines, so the oldest of them (Playing) is past the limit.
        lines.hideStreaming = false
        let all = lines.shown(.osc)
        #expect(all.count == 20_000)
        #expect(all.first?.message == "OSC <- /Syndicate/Deck/1/Progress 0.101")
        #expect(all.last?.message == "OSC <- /Syndicate/Deck/1/Progress 0.20100")
    }

    @Test("The monitor says which notes it hides, so a quiet port doesn't look dead; with none hidden it says nothing")
    func hiddenNotesHint() {
        #expect(DiagnosticsTab.hiddenNotesHint([52]) == "Note 52, the controller's idle heartbeat, is hidden.")
        #expect(DiagnosticsTab.hiddenNotesHint([52, 53]) == "Notes 52 and 53, which the controller sends on its own, are hidden.")
        #expect(DiagnosticsTab.hiddenNotesHint([]) == nil)
    }

    // #162: the visible tab, as plain text to copy or save.

    @Test("A tab's plain text is its shown lines, oldest first, each ending in a newline; UNMAPPED keeps its words only")
    func plainText() {
        var lines = DiagnosticsLines()
        lines.append(to: .monitor, message: "12:00:01.000  1  Note On  1 127  ", label: "play")
        lines.append(to: .monitor, message: "12:00:02.000  1  Note On 99 127  ", label: "UNMAPPED", isUnmapped: true)
        lines.append(to: .osc, message: "OSC -> /Syndicate/Deck/1/PlayPause 1")
        #expect(lines.plainText(.monitor) == "12:00:01.000  1  Note On  1 127  play\n12:00:02.000  1  Note On 99 127  UNMAPPED\n")
        #expect(lines.plainText(.sweep) == "")
    }

    @Test("The OSC tab's plain text follows the streaming filter, both ways")
    func plainTextFollowsFilter() {
        var lines = DiagnosticsLines()
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Playing 1")
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Progress 0.25")
        lines.append(to: .osc, message: "OSC -> /Syndicate/Deck/1/PlayPause 1")
        #expect(lines.plainText(.osc) == "OSC <- /Syndicate/Deck/1/Playing 1\nOSC -> /Syndicate/Deck/1/PlayPause 1\n")
        lines.hideStreaming = false
        #expect(lines.plainText(.osc)
            == "OSC <- /Syndicate/Deck/1/Playing 1\nOSC <- /Syndicate/Deck/1/Progress 0.25\nOSC -> /Syndicate/Deck/1/PlayPause 1\n")
    }

    @Test("Save… suggests the app's name and the tab's, as a .txt file", arguments: [
        (DiagnosticsTab.monitor, "DeckBridge MIDI Monitor.txt"),
        (.sweep, "DeckBridge LED Sweep.txt"),
        (.osc, "DeckBridge OSC Log.txt"),
    ])
    func exportFileName(tab: DiagnosticsTab, name: String) {
        #expect(tab.exportFileName(appName: "DeckBridge") == name)
    }
}
