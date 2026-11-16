import ControllerBridgePresentation
import Testing

/// Which light is which, by type, so views and the spoken text never match on display words (#171).
@Suite("Status light kinds")
struct StatusLightKindTests {
    @Test("Each light the bridge writes says what it is: controller, feedback, demo, bridge, tempo")
    func kinds() {
        let running = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096),
                                                     deck: 1, master: true, demo: true))
        #expect(running.lights.map(\.kind) == [.demo, .controller, .feedback])
        #expect(running.master?.kind == .tempo)

        let stopped = StatusPresentation(BridgeState(controller: .notConnected, feedback: .live(port: 9096), deck: 1, stopped: true))
        #expect(stopped.lights.map(\.kind) == [.bridge])
    }

    @Test("A MIDI device that no profile matches is a device light")
    func device() {
        #expect(StatusLight(unmatchedDevice: "DDJ-FLX4").kind == .device)
    }
}
