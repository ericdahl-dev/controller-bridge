import ControllerBridgePresentation
import Testing

/// The menu's status in Syndicate's words. Status is always a dot plus a word, never color alone.
@Suite("Status presentation")
struct StatusPresentationTests {
    @Test("Connected and live: both lights green, the icon is OK, and the status line reads like Syndicate's")
    func connectedAndLive() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1))
        #expect(status.line == "CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
        #expect(status.lights == [
            StatusLight(label: "CONTROLLER", word: "CONNECTED", tone: .live),
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
        // 63 characters with DECK: over the panel's budget, so DECK drops first (#66).
        #expect(status.line == "CONTROLLER ● CONNECTED · FEEDBACK ● PORT 9096 IN USE")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "PORT 9096 IN USE", tone: .error))
        #expect(status.icon == .error)
    }

    @Test("Feedback still starting is a gray STARTING; a listener that failed for another reason is a red FAILED")
    func feedbackStartingAndFailed() {
        let starting = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .starting, deck: 1))
        #expect(starting.lights.last == StatusLight(label: "FEEDBACK", word: "STARTING", tone: .idle))
        #expect(starting.icon == .attention)

        let failed = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .failed, deck: 1))
        #expect(failed.line == "CONTROLLER ● CONNECTED · FEEDBACK ● FAILED · DECK [1]")
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
        #expect(status.line == "BRIDGE ● STOPPED · DECK [1]")   // only the BRIDGE light (#66)
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
        #expect(status.line == "CONTROLLER ● CONNECTED · FEEDBACK ● WAITING · DECK [1]")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "WAITING", tone: .idle))
        #expect(status.icon == .attention)
    }

    @Test("Syndicate stopped answering (#21): an orange DROPPED light (not STOPPED: BRIDGE ● STOPPED is the red error), the icon asks for attention, and the dropout shows")
    func feedbackStopped() {
        let status = StatusPresentation(BridgeState(
            controller: .connected(profile: "LC6000"), feedback: .stopped(port: 9096), deck: 1,
            lastDropout: "21:14"
        ))
        #expect(status.line == "CONTROLLER ● CONNECTED · FEEDBACK ● DROPPED · DECK [1]")
        #expect(status.lights.last == StatusLight(label: "FEEDBACK", word: "DROPPED", tone: .attention))
        #expect(status.icon == .attention)
        // A caption and a value, not a sentence in capitals (#66): the panel shows LAST DROPOUT over 21:14.
        #expect(status.lastDropout == CaptionedValue(caption: "Last dropout", value: "21:14"))
    }

    @Test("With no dropout yet, there is no dropout line")
    func noDropoutLine() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1))
        #expect(status.lastDropout == nil)
    }

    @Test("Tempo master (#53): an orange MASTER light, \"· MASTER\" ends the status line, and the icon stays OK")
    func master() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1, master: true))
        #expect(status.master == StatusLight(label: "TEMPO", word: "MASTER", tone: .attention))
        // 60 characters with DECK: over the panel's budget, so DECK drops first and MASTER still ends the line (#66).
        #expect(status.line == "CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · MASTER")
        #expect(status.icon == .ok)

        let notMaster = StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1))
        #expect(notMaster.master == nil)
        #expect(notMaster.line == "CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
    }

    @Test("Demo mode (#64): a leading orange DEMO ● CONTROLLER light, DEMO in the status line, and the icon on attention")
    func demo() {
        let status = StatusPresentation(BridgeState(
            controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1, demo: true
        ), lineBudget: 100)
        #expect(status.lights == [
            StatusLight(label: "DEMO", word: "CONTROLLER", tone: .attention),
            StatusLight(label: "CONTROLLER", word: "CONNECTED", tone: .live),
            StatusLight(label: "FEEDBACK", word: "LIVE", tone: .live),
        ])
        #expect(status.line == "DEMO ● CONTROLLER · CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
        // An exception to "the icon is for problems": DEMO must never be mistaken for real hardware.
        #expect(status.icon == .attention)
    }

    // The status line fits a character budget (#66): whole parts drop in priority order (DEMO and error lights, then the
    // controller, feedback, MASTER, DECK), and a word is never cut. Expected lines are written out by hand.

    static let demoMaster = BridgeState(
        controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1, master: true, demo: true
    )

    @Test("DEMO and MASTER: the line drops DECK, then MASTER, then FEEDBACK, then the controller, as the budget shrinks")
    func lineFitsBudget() {
        #expect(StatusPresentation(Self.demoMaster, lineBudget: 100).line
            == "DEMO ● CONTROLLER · CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1] · MASTER")
        #expect(StatusPresentation(Self.demoMaster, lineBudget: 75).line
            == "DEMO ● CONTROLLER · CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · MASTER")
        #expect(StatusPresentation(Self.demoMaster, lineBudget: 65).line
            == "DEMO ● CONTROLLER · CONTROLLER ● CONNECTED · FEEDBACK ● LIVE")
        #expect(StatusPresentation(Self.demoMaster, lineBudget: 45).line == "DEMO ● CONTROLLER · CONTROLLER ● CONNECTED")
        // The top part always stays whole, even over budget: a word is never cut.
        #expect(StatusPresentation(Self.demoMaster, lineBudget: 10).line == "DEMO ● CONTROLLER")
    }

    @Test("An error light outranks the controller: a taken feedback port stays when the line is short")
    func errorStays() {
        let state = BridgeState(controller: .connected(profile: "LC6000"), feedback: .portInUse(port: 9096), deck: 1, master: true)
        #expect(StatusPresentation(state, lineBudget: 30).line == "FEEDBACK ● PORT 9096 IN USE")
    }

    @Test("The parts the status bar draws are exactly the line's parts, in order, with each word's tone")
    func linePartsMatchLine() {
        let status = StatusPresentation(Self.demoMaster, lineBudget: 75)
        #expect(status.lineParts == [
            StatusLinePart(label: "DEMO", word: "CONTROLLER", tone: .attention),
            StatusLinePart(label: "CONTROLLER", word: "CONNECTED", tone: .live),
            StatusLinePart(label: "FEEDBACK", word: "LIVE", tone: .live),
            StatusLinePart(label: nil, word: "MASTER", tone: .attention),
        ])
    }

    // #66: the panel design pass.

    @Test("A stopped bridge shows only BRIDGE ● STOPPED: nothing is starting or connecting, so those lights would mislead")
    func stoppedShowsOnlyBridge() {
        let status = StatusPresentation(BridgeState(controller: .notConnected, feedback: .starting, deck: 1, stopped: true))
        #expect(status.lights == [StatusLight(label: "BRIDGE", word: "STOPPED", tone: .error)])
        #expect(status.line == "BRIDGE ● STOPPED · DECK [1]")
        #expect(status.icon == .error)
    }

    @Test("Unplugged after a connection is an orange CONTROLLER ● UNPLUGGED, so a DJ notices; never connected stays gray")
    func unplugged() {
        let unplugged = StatusPresentation(BridgeState(controller: .unplugged(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1))
        #expect(unplugged.lights.first == StatusLight(label: "CONTROLLER", word: "UNPLUGGED", tone: .attention))
        #expect(unplugged.icon == .attention)
        let never = StatusPresentation(BridgeState(controller: .notConnected, feedback: .live(port: 9096), deck: 1))
        #expect(never.lights.first == StatusLight(label: "CONTROLLER", word: "NOT CONNECTED", tone: .idle))
    }

    @Test("The header names the controller (not the app), with the last event under it; the light label stays CONTROLLER")
    func header() {
        let connected = StatusPresentation(BridgeState(
            controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1, lastEvent: "Connected DENON LC6000 PRIME"
        ))
        #expect(connected.header == StatusHeader(title: "Denon LC6000 PRIME", subtitle: "Connected DENON LC6000 PRIME"))
        #expect(connected.lights.first?.label == "CONTROLLER")

        let unplugged = StatusPresentation(BridgeState(
            controller: .unplugged(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1, lastEvent: "Unplugged at 21:14"
        ))
        #expect(unplugged.header == StatusHeader(title: "Denon LC6000 PRIME", subtitle: "Unplugged at 21:14"))
        #expect(StatusPresentation(BridgeState(controller: .notConnected, feedback: .live(port: 9096), deck: 1)).header
            == StatusHeader(title: "No controller", subtitle: nil))
        // Unplugged with its name no longer known: say what happened, not "No controller".
        #expect(StatusPresentation(BridgeState(controller: .unplugged(profile: nil), feedback: .live(port: 9096), deck: 1)).header.title
            == "Controller unplugged")
    }

    @Test("Two controllers (#25): a block each with its own header, light and deck; the line lists both decks")
    func twoControllers() {
        let state = BridgeState(
            controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1,
            others: [BridgeState.ControllerEntry(controller: .unplugged(profile: "Denon LC6000 PRIME"), deck: 3, lastEvent: "Unplugged at 21:14")]
        )
        let status = StatusPresentation(state)
        #expect(status.blocks == [
            ControllerBlock(
                header: StatusHeader(title: "Denon LC6000 PRIME", subtitle: nil),
                light: StatusLight(label: "CONTROLLER", word: "CONNECTED", tone: .live), deck: 1
            ),
            ControllerBlock(
                header: StatusHeader(title: "Denon LC6000 PRIME", subtitle: "Unplugged at 21:14"),
                light: StatusLight(label: "CONTROLLER", word: "UNPLUGGED", tone: .attention), deck: 3
            ),
        ])
        // With more than one controller the line shows the worst of them, counted, so an unplugged second one shows (#89).
        #expect(status.line == "CONTROLLERS ● 1 UNPLUGGED · FEEDBACK ● LIVE · DECKS 1 3")
        #expect(status.lineParts.first == StatusLinePart(label: "CONTROLLERS", word: "1 UNPLUGGED", tone: .attention))
        // An unplugged second controller still needs a look.
        #expect(status.icon == .attention)
    }

    @Test("Quit asks first only while feedback is LIVE, when quitting would stop a working set (#66)")
    func quitAsks() {
        func asks(_ feedback: BridgeState.Feedback) -> Bool {
            StatusPresentation(BridgeState(controller: .connected(profile: "LC6000"), feedback: feedback, deck: 1)).quitAsks
        }
        #expect(asks(.live(port: 9096)))
        #expect(!asks(.waiting(port: 9096)))
        #expect(!asks(.stopped(port: 9096)))
        #expect(!asks(.portInUse(port: 9096)))
        #expect(!asks(.starting))
    }

    @Test("The deck picker: on normally; off with the reason in demo mode, so a click can't queue a jump for later (#90)")
    func deckPicker() {
        func picker(demo: Bool = false, stopped: Bool = false) -> DeckPickerState {
            StatusPresentation(BridgeState(
                controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 1, stopped: stopped, demo: demo
            )).deckPicker
        }
        #expect(picker() == .enabled)
        #expect(picker(demo: true) == .disabled(reason: "Demo controller is on, so the deck stays put."))
        // A stopped bridge has nothing to switch.
        #expect(picker(stopped: true) == .hidden)
    }

    // #91: what the controller's status means for the panel, from the values Core reports. lastEvent texts are the
    // Coordinator's own.

    @Test("Connected uses the profile in use")
    func mapConnected() {
        #expect(BridgeState.Controller(connected: true, profile: "Denon LC6000 PRIME", lastProfile: "Denon LC6000 PRIME", lastDisconnect: nil)
            == .connected(profile: "Denon LC6000 PRIME"))
    }

    @Test("An unplug keeps the controller's name: the header still says Denon LC6000 PRIME")
    func mapUnplugged() {
        let controller = BridgeState.Controller(connected: false, profile: nil, lastProfile: "Denon LC6000 PRIME", lastDisconnect: .unplugged)
        #expect(controller == .unplugged(profile: "Denon LC6000 PRIME"))
        let status = StatusPresentation(BridgeState(
            controller: controller, feedback: .live(port: 9096), deck: 1, lastEvent: "Disconnected DENON LC6000 PRIME"
        ))
        #expect(status.header == StatusHeader(title: "Denon LC6000 PRIME", subtitle: "Disconnected DENON LC6000 PRIME"))
        #expect(status.lights.first == StatusLight(label: "CONTROLLER", word: "UNPLUGGED", tone: .attention))
    }

    @Test("A send or read failure is MIDI ERROR, not UNPLUGGED, and the help says what to check first")
    func mapFailed() {
        for reason: BridgeState.Disconnect in [.sendFailed, .inputFailed] {
            let controller = BridgeState.Controller(connected: false, profile: nil, lastProfile: "Denon LC6000 PRIME", lastDisconnect: reason)
            #expect(controller == .failed(profile: "Denon LC6000 PRIME"))
            let state = BridgeState(controller: controller, feedback: .live(port: 9096), deck: 1,
                                    lastEvent: "Disconnected DENON LC6000 PRIME (MIDI send failed)")
            #expect(StatusPresentation(state).lights.first == StatusLight(label: "CONTROLLER", word: "MIDI ERROR", tone: .attention))
            #expect(HelpMessage(state) == HelpMessage(
                text: "Lost contact with the controller. Check the USB cable, then unplug and replug.", showsGuide: false
            ))
        }
    }

    @Test("After a device change in Settings it's a gray WAITING, not a problem")
    func mapWaiting() {
        let controller = BridgeState.Controller(connected: false, profile: nil, lastProfile: "Denon LC6000 PRIME", lastDisconnect: .deviceChanged)
        #expect(controller == .waiting(profile: "Denon LC6000 PRIME"))
        let state = BridgeState(controller: controller, feedback: .live(port: 9096), deck: 1)
        #expect(StatusPresentation(state).lights.first == StatusLight(label: "CONTROLLER", word: "WAITING", tone: .idle))
        #expect(HelpMessage(state) == HelpMessage(text: "Waiting for the device chosen in Settings.", showsGuide: false))
    }

    @Test("Never connected, removed in Settings, or stopped: NOT CONNECTED")
    func mapNotConnected() {
        for reason: BridgeState.Disconnect? in [nil, .removed, .stopped] {
            #expect(BridgeState.Controller(connected: false, profile: nil, lastProfile: nil, lastDisconnect: reason) == .notConnected)
        }
    }

    // #88: a stopped bridge says which part failed, shows no MASTER, and offers no demo.

    @Test("Stopped with master set: no MASTER light and no MASTER in the line")
    func stoppedHidesMaster() {
        let status = StatusPresentation(BridgeState(
            controller: .connected(profile: "LC6000"), feedback: .live(port: 9096), deck: 2, stopped: true, master: true
        ))
        #expect(status.master == nil)
        #expect(status.line == "BRIDGE ● STOPPED · DECK [2]")
    }

    @Test("The stopped header names the bridge problem, not \"No controller\"", arguments: [
        (BridgeState.StopReason.midi, "Couldn't open MIDI"),
        (.oscSender, "Couldn't reach Syndicate"),
        (.profiles, "Couldn't load profiles"),
    ])
    func stoppedHeader(reason: BridgeState.StopReason, subtitle: String) {
        let status = StatusPresentation(BridgeState(
            controller: .notConnected, feedback: .starting, deck: 1, stopped: true, stopReason: reason
        ))
        #expect(status.header == StatusHeader(title: "Bridge stopped", subtitle: subtitle))
        // The panel draws each block's header, so the first block says it too.
        #expect(status.blocks.first?.header == StatusHeader(title: "Bridge stopped", subtitle: subtitle))
    }

    @Test("The demo toggle is offered only while the bridge runs: stopped, there's nothing to switch it on with")
    func demoToggleHiddenWhenStopped() {
        #expect(StatusPresentation(BridgeState(controller: .notConnected, feedback: .starting, deck: 1)).showsDemoToggle)
        #expect(!StatusPresentation(BridgeState(controller: .notConnected, feedback: .starting, deck: 1, stopped: true)).showsDemoToggle)
    }

    @Test("Four controllers keep their decks in the line: FEEDBACK makes way, as it's in the lights above (#89)")
    func fourControllers() {
        let others = (2...4).map { BridgeState.ControllerEntry(controller: .connected(profile: "Denon LC6000 PRIME"), deck: $0) }
        let state = BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1, others: others)
        #expect(StatusPresentation(state).line == "CONTROLLERS ● 4 CONNECTED · DECKS 1 2 3 4")
    }

    @Test("One controller keeps today's line: CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
    func oneControllerLine() {
        let state = BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 1)
        #expect(StatusPresentation(state).line == "CONTROLLER ● CONNECTED · FEEDBACK ● LIVE · DECK [1]")
    }
}
