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

    @Test("Each list keeps its newest 500 lines")
    func limit() {
        var lines = DiagnosticsLines()
        for n in 1...501 { lines.append(to: .osc, message: "OSC -> /Syndicate/Browser/Down \(n)") }
        let shown = lines.shown(.osc)
        #expect(shown.count == 500)
        #expect(shown.first?.message == "OSC -> /Syndicate/Browser/Down 2")
    }

    @Test("Progress and Time feedback are hidden by default, and shown when the box is unticked")
    func hideProgressAndTime() {
        var lines = DiagnosticsLines()
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Progress 0.25")
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Time 61")
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Playing 1")
        #expect(lines.shown(.osc).map(\.message) == ["OSC <- /Syndicate/Deck/1/Playing 1"])
        lines.hideProgressAndTime = false
        #expect(lines.shown(.osc).count == 3)
    }

    @Test("Hidden Progress and Time lines can't push the rest out: after 600 of them, the Playing line is still shown (#97)")
    func hiddenLinesDontEvict() {
        var lines = DiagnosticsLines()
        lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Playing 1")
        for n in 1...600 { lines.append(to: .osc, message: "OSC <- /Syndicate/Deck/1/Progress 0.\(n)") }
        #expect(lines.shown(.osc).map(\.message) == ["OSC <- /Syndicate/Deck/1/Playing 1"])

        // Unticking the box shows everything in arrival order, newest 500: 501 lines in, so the oldest (Playing) and the
        // first 100 Progress lines are past the limit; Progress 0.101 through 0.600 remain.
        lines.hideProgressAndTime = false
        let all = lines.shown(.osc)
        #expect(all.count == 500)
        #expect(all.first?.message == "OSC <- /Syndicate/Deck/1/Progress 0.101")
        #expect(all.last?.message == "OSC <- /Syndicate/Deck/1/Progress 0.600")
    }

    @Test("The monitor says which notes it hides, so a quiet port doesn't look dead; with none hidden it says nothing")
    func hiddenNotesHint() {
        #expect(DiagnosticsTab.hiddenNotesHint([52]) == "Note 52, the controller's idle heartbeat, is hidden.")
        #expect(DiagnosticsTab.hiddenNotesHint([52, 53]) == "Notes 52 and 53, which the controller sends on its own, are hidden.")
        #expect(DiagnosticsTab.hiddenNotesHint([]) == nil)
    }
}
