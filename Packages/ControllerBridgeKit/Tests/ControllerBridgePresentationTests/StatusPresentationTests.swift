import ControllerBridgePresentation
import Testing

/// The menu's status in Syndicate's words. Status is always a dot plus a word, never color alone.
@Suite("Status presentation")
struct StatusPresentationTests {
    @Test("Connected and live: both lights green, the icon is OK, and the status line reads like Syndicate's")
    func connectedAndLive() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1))
        #expect(status.line == "LC6000 ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
        #expect(status.lights == [
            StatusLight(label: "LC6000", word: "CONNECTED", tone: .live),
            StatusLight(label: "FEEDBACK", word: "LIVE", tone: .live),
        ])
        #expect(status.icon == .ok)
    }

    @Test("No controller: a gray NOT CONNECTED light under a generic label, and the icon asks for attention")
    func notConnected() {
        let status = StatusPresentation(BridgeState(controller: .notConnected, feedback: .live(port: 9096), deck: 2))
        #expect(status.line == "CONTROLLER ● NOT CONNECTED · FEEDBACK ● LIVE · DECK [2]")
        #expect(status.lights.first == StatusLight(label: "CONTROLLER", word: "NOT CONNECTED", tone: .idle))
        #expect(status.icon == .attention)
    }

    @Test("Feedback port taken: a red PORT 9096 IN USE light, and the icon shows an error")
    func portInUse() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .portInUse(port: 9096), deck: 1))
        #expect(status.line == "LC6000 ● CONNECTED · FEEDBACK ● PORT 9096 IN USE · DECK [1]")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "PORT 9096 IN USE", tone: .error))
        #expect(status.icon == .error)
    }

    @Test("A device with no matching profile (#43): an orange NO PROFILE light under the device's name")
    func noProfile() {
        let status = StatusPresentation(BridgeState(controller: .noProfile(device: "DDJ-FLX4"), feedback: .live(port: 9096), deck: 1))
        #expect(status.line == "DDJ-FLX4 ● NO PROFILE · FEEDBACK ● LIVE · DECK [1]")
        #expect(status.lights.first == StatusLight(label: "DDJ-FLX4", word: "NO PROFILE", tone: .attention))
        #expect(status.icon == .attention)
    }

    @Test("Feedback still starting is a gray STARTING; a listener that failed for another reason is a red FAILED")
    func feedbackStartingAndFailed() {
        let starting = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .starting, deck: 1))
        #expect(starting.lights.last == StatusLight(label: "FEEDBACK", word: "STARTING", tone: .idle))
        #expect(starting.icon == .attention)

        let failed = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .failed, deck: 1))
        #expect(failed.line == "LC6000 ● CONNECTED · FEEDBACK ● FAILED · DECK [1]")
        #expect(failed.icon == .error)
    }

    @Test("Each tone has its dot color: green, caption gray, Syndicate orange, muted red", arguments: [
        (StatusLight.Tone.live, 0x72CD8B),
        (.idle, 0xA9AAAA),
        (.attention, 0xF19741),
        (.error, 0xE06C6C),
    ] as [(StatusLight.Tone, UInt32)])
    func toneColors(tone: StatusLight.Tone, hex: UInt32) {
        #expect(tone.color == RGB(hex: hex))
    }

    @Test("If the bridge couldn't start (no mapping, CoreMIDI or OSC sender), a red STOPPED light leads and the icon shows an error")
    func stoppedByAStartupProblem() {
        let status = StatusPresentation(BridgeState(controller: .notConnected, feedback: .starting, deck: 1, stopped: true))
        #expect(status.line == "BRIDGE ● STOPPED · CONTROLLER ● NOT CONNECTED · FEEDBACK ● STARTING · DECK [1]")
        #expect(status.lights.first == StatusLight(label: "BRIDGE", word: "STOPPED", tone: .error))
        #expect(status.icon == .error)
    }

    @Test("A MIDI device no profile matches (#43) gets its own orange NO PROFILE row, so an IAC bus never hides the controller light")
    func unmatchedDeviceRow() {
        #expect(StatusLight(unmatchedDevice: "DDJ-FLX4") == StatusLight(label: "DDJ-FLX4", word: "NO PROFILE", tone: .attention))
    }

    @Test("Listening, but Syndicate hasn't answered since launch (#21): a gray WAITING, and the icon asks for attention")
    func feedbackWaiting() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .waiting(port: 9096), deck: 1))
        #expect(status.line == "LC6000 ● CONNECTED · FEEDBACK ● WAITING · DECK [1]")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "WAITING", tone: .idle))
        #expect(status.icon == .attention)
    }

    @Test("Syndicate stopped answering (#21): an orange DROPPED light (not STOPPED: BRIDGE ● STOPPED is the red error), the icon asks for attention, and the dropout shows")
    func feedbackStopped() {
        let status = StatusPresentation(BridgeState(
            controller: .connected(profile: "LC6000"), feedback: .stopped(port: 9096), deck: 1,
            lastDropout: "Syndicate feedback stopped"
        ))
        #expect(status.line == "LC6000 ● CONNECTED · FEEDBACK ● DROPPED · DECK [1]")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "DROPPED", tone: .attention))
        #expect(status.icon == .attention)
        #expect(status.lastDropout == "LAST DROPOUT: Syndicate feedback stopped")
    }

    @Test("With no dropout yet, there is no dropout line")
    func noDropoutLine() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1))
        #expect(status.lastDropout == nil)
    }
}
