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

    @Test("A device named like one of the bridge's own lights is still a device: the kind never comes from the words")
    func deviceNamedController() {
        #expect(StatusLight(unmatchedDevice: "Controller").kind == .device)
        #expect(StatusLight(unmatchedDevice: "Controller").spoken == "Controller: no profile")
    }
}

@Suite("Status words in natural case")
struct NaturalCaseLineTests {
    @Test("Several controllers count the worst word mid-sentence, and an acronym keeps its caps: 1 MIDI error")
    func acronymAfterCount() {
        let state = BridgeState(
            controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1,
            others: [BridgeState.ControllerEntry(controller: .failed(profile: "Denon LC6000 PRIME"), deck: 3)]
        )
        #expect(StatusPresentation(state).lineParts.first == StatusLinePart(label: "Controllers", word: "1 MIDI error", tone: .attention))
    }
}
