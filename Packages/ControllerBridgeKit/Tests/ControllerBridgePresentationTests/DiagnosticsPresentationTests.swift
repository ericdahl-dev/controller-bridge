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
}
