/// Runs the Bridges (one per controller) against the MIDI system, the OSC sender, a clock and a log.
///
/// Not thread-safe on purpose: the app confines it to one serial consumer that feeds it MIDI, feedback and ticks in
/// order. Tests call it directly.
public final class Coordinator {
    private let midiSystem: any MIDISystem
    private let osc: any OSCSender
    private let clock: any Clock
    private let log: any LogSink
    private var controllers: [Controller]
    /// The controller profiles a device can match.
    private let profiles: [ControllerProfile]
    /// Unmatched devices already logged, so a device-list change doesn't log them again.
    private var loggedUnmatched: Set<MIDIEndpoint.ID> = []
    /// Devices matching more than one profile, already logged.
    private var loggedAmbiguous: Set<MIDIEndpoint.ID> = []
    private var bridges: [Bridge] { controllers.map(\.bridge) }

    /// When the last feedback message arrived, if any has (#21).
    private var lastFeedbackAt: Double?
    /// When the last Resend went out, while it waits for an answer. Any feedback is the answer.
    private var resendSentAt: Double?

    /// Set while the Diagnostics window is open (#26); nil otherwise, so nothing is built for it during a set.
    /// The LED sweep in progress: when it started, its steps and the next one to send.
    private var sweep: (start: Double, steps: [LEDSweep.Step], next: Int)?

    public var diagnostics: ((DiagnosticEvent) -> Void)? {
        didSet { (osc as? OSCTap)?.onSend = diagnostics.map { sink in { sink(.oscOut($0)) } } }
    }
    /// Settings' LEDs switch, kept so a Bridge rebuilt for another profile honors it.
    private var ledsEnabled = true

    /// What the menu shows. The app copies it after each call.
    public private(set) var status: CoordinatorStatus

    /// A Bridge and the devices it is connected to.
    private struct Controller {
        var bridge: Bridge
        /// The profile the bridge runs, chosen by the connected device's name.
        var profile: ControllerProfile
        var source: MIDIEndpoint?
        /// The unique id of the last source this controller used, so a replug finds the same unit first.
        var knownSourceID: MIDIEndpoint.ID?
        /// The devices picked in Settings (#19). Nil is automatic: the first device a profile matches.
        var chosenInput: MIDIEndpoint.ID?
        var chosenOutput: MIDIEndpoint.ID?
        /// The MIDI channel picked in Settings (#25), 1-16, or nil for the profile's.
        var channel: Int?
        /// The destination its LEDs go to, once open.
        var destination: MIDIEndpoint?
    }

    /// One controller, whose profile is chosen by the name of the device that connects. Until one does, it runs the
    /// first profile. `profiles` must not be empty.
    public init(profiles: [ControllerProfile], midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        precondition(!profiles.isEmpty, "A Coordinator needs at least one controller profile")
        self.midiSystem = midi
        // Every Bridge sends through the tap, so the OSC log sees what goes out while Diagnostics is open.
        self.osc = OSCTap(osc)
        self.clock = clock
        self.log = log
        self.profiles = profiles
        let first = profiles[0]
        controllers = [Controller(bridge: Bridge(mapping: first.mapping, osc: self.osc, clock: clock), profile: first)]
        status = CoordinatorStatus(controllers: [ControllerStatus(deck: first.mapping.deck.number, connected: false)])
    }

    /// One controller running `mapping`, matched to a device whose name contains `mapping.midi.input`.
    public convenience init(mapping: Mapping, midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        let profile = ControllerProfile(id: "custom", name: "Custom mapping", deviceHints: [mapping.midi.input], mapping: mapping)
        self.init(profiles: [profile], midi: midi, osc: osc, clock: clock, log: log)
    }

    /// Opens each controller's ports, asks Syndicate for its state and paints the LEDs. Starting with no controller
    /// connected is not an error: it connects when it appears.
    public func start() {
        refreshDevices()
        for index in controllers.indices {
            if !connect(index) {
                log.log("No controller matching \"\(controllers[index].bridge.mapping.midi.input)\" yet")
            }
            controllers[index].bridge.start()
        }
        requestResend()
    }

    /// The MIDI devices changed. Re-reads them, connecting controllers that appeared.
    public func devicesChanged() {
        refreshDevices()
        for index in controllers.indices {
            if let source = controllers[index].source {
                if !midiSystem.sources.contains(where: { $0.id == source.id }) { disconnect(index) }
            } else if connect(index) {
                controllers[index].bridge.start()
                requestResend()
            }
        }
        disconnectFailedOutputs()
    }

    /// Reading from a source failed, such as a reconnect that couldn't attach. Counts as that controller's unplug.
    public func inputFailed(source: MIDIEndpoint.ID) {
        for index in controllers.indices where controllers[index].source?.id == source {
            disconnect(index, reason: "MIDI input failed")
        }
    }

    /// Releases everything the controller held, exactly once, and closes its ports.
    private func disconnect(_ index: Int, reason: String? = nil) {
        guard let source = controllers[index].source else { return }
        let bridge = controllers[index].bridge
        bridge.releaseAll()
        controllers[index].source = nil
        let destination = controllers[index].destination
        controllers[index].destination = nil
        // Another controller on the same device, on another channel (#25), keeps it open.
        if !controllers.contains(where: { $0.source?.id == source.id }) { midiSystem.disconnect(source: source) }
        if destination == nil || !controllers.contains(where: { $0.destination?.id == destination?.id }) { bridge.output?.close() }
        bridge.output = nil
        status.controllers[index].profile = nil
        report(index, "Disconnected \(source.name)" + (reason.map { " (\($0))" } ?? ""))
    }

    /// Opens the controller's ports if a matching device is present. Returns whether its input is connected.
    private func connect(_ index: Int) -> Bool {
        let sources = midiSystem.sources
        let source: MIDIEndpoint?
        if let chosen = controllers[index].chosenInput {
            source = sources.first { $0.id == chosen }
        } else {
            // Automatic: a unit another controller already has stays with it.
            let claimed = Set(controllers.indices.filter { $0 != index }.compactMap { controllers[$0].source?.id })
            let free = sources.filter { !claimed.contains($0.id) }
            let known = controllers[index].knownSourceID.flatMap { id in free.first { $0.id == id } }
            source = known ?? free.first { ControllerProfile.matching($0.name, in: profiles) != nil }
        }
        guard let source else { return false }
        // A device picked in Settings runs even if no profile names it: then it keeps the current profile.
        let matchedProfile = ControllerProfile.matching(source.name, in: profiles)
        guard let profile = matchedProfile ?? (controllers[index].chosenInput != nil ? controllers[index].profile : nil) else {
            return false
        }
        if profile != controllers[index].profile {
            controllers[index].profile = profile
            controllers[index].bridge = makeBridge(profile, for: index)
        }
        let bridge = controllers[index].bridge
        do {
            if !controllers.contains(where: { $0.source?.id == source.id }) { try midiSystem.connect(source: source) }
        } catch {
            log.log("Couldn't open MIDI input \(source.name): \(error)")
            return false
        }
        controllers[index].source = source
        controllers[index].knownSourceID = source.id
        status.controllers[index].profile = profile.name
        let destinations = midiSystem.destinations
        let chosenOutput = controllers[index].chosenOutput.flatMap { id in destinations.first { $0.id == id } }
        let taken = Set(controllers.indices.filter { $0 != index }.compactMap { controllers[$0].destination?.id })
        let freeDestinations = controllers[index].chosenInput == nil ? destinations.filter { !taken.contains($0.id) } : destinations
        if let destination = chosenOutput ?? Self.match(freeDestinations, bridge.mapping.midi.output) {
            do {
                bridge.output = try midiSystem.openOutput(destination: destination)
                controllers[index].destination = destination
            } catch {
                log.log("Couldn't open MIDI output \(destination.name): \(error)")
            }
        }
        report(index, "Connected \(source.name)")
        return true
    }

    /// Lists every MIDI source with the profile it matches. A source that matches none is listed, not bridged.
    private func refreshDevices() {
        status.devices = midiSystem.sources.map { source in
            if let profile = ControllerProfile.matching(source.name, in: profiles) {
                let names = ControllerProfile.candidates(source.name, in: profiles).map(\.profile.name)
                if names.count > 1, loggedAmbiguous.insert(source.id).inserted {
                    log.log("\(source.name) matches \(names.joined(separator: " and ")); using \(profile.name), whose hint is longest.")
                }
                return DeviceStatus(name: source.name, profile: profile.name, note: nil)
            }
            let note = "No controller profile matches \(source.name), so it isn't bridged."
            if loggedUnmatched.insert(source.id).inserted { log.log(note) }
            return DeviceStatus(name: source.name, profile: nil, note: note)
        }
    }

    private func report(_ index: Int, _ event: String) {
        log.log(event)
        status.controllers[index].connected = controllers[index].source != nil
        status.controllers[index].lastEvent = event
    }

    /// Releases everything held in Syndicate. Safe to call again: a second call sends nothing.
    public func stop() {
        for index in controllers.indices {
            controllers[index].bridge.releaseAll()
            disconnect(index)
        }
    }

    /// The Mac is about to sleep: release everything held, since the controller may be gone on wake.
    public func willSleep() {
        for bridge in bridges { bridge.releaseAll() }
    }

    /// The Mac woke: the devices may have changed while it slept.
    public func didWake() {
        devicesChanged()
    }

    /// Runs timers, such as releasing a jog nudge after the wheel stops. The app calls it about every 10 ms.
    public func tick() {
        runSweep()
        for bridge in bridges { bridge.tick() }
        checkLiveness()
        disconnectFailedOutputs()
    }

    /// The first endpoint whose name contains `wanted`, ignoring case.
    private static func match(_ endpoints: [MIDIEndpoint], _ wanted: String) -> MIDIEndpoint? {
        endpoints.first { $0.name.lowercased().contains(wanted.lowercased()) }
    }

    /// A MIDI message from a source. Only the controller connected to that source handles it.
    public func midi(_ event: MIDIEvent, source: MIDIEndpoint.ID) {
        if let diagnostics {
            let mapping = (controllers.first { $0.source?.id == source } ?? controllers[0]).bridge.mapping
            diagnostics(.midiIn(event, label: mapping.monitorName(for: event), at: clock.now))
        }
        for controller in controllers where controller.source?.id == source { controller.bridge.handle(event) }
        disconnectFailedOutputs()
    }

    /// An OSC feedback message from Syndicate. One listener fans out to every Bridge.
    public func feedback(_ message: OSCMessage) {
        diagnostics?(.oscIn(message))
        feedbackArrived()
        for bridge in bridges { bridge.handle(message) }
        for index in controllers.indices { status.controllers[index].master = controllers[index].bridge.isMaster }
        disconnectFailedOutputs()
    }

    /// A failed MIDI send means the controller is gone, even before CoreMIDI says so.
    private func disconnectFailedOutputs() {
        for index in controllers.indices where controllers[index].bridge.outputFailed {
            disconnect(index, reason: "MIDI send failed")
        }
    }

    // MARK: Feedback liveness (#21)

    // Syndicate sends feedback only when a value changes, so after a quiet spell the bridge asks for a resend: a live
    // Syndicate answers with every subscribed value, and always ColorPalette (user guide §14.10).

    /// The OSC settings are shared by every controller; the first one's mapping holds them until Settings (#19).
    private var oscSettings: Mapping.OSC { controllers[0].bridge.mapping.osc }

    private func feedbackArrived() {
        let now = clock.now
        let wasStale = status.feedback == .stale
        // An answer to a Resend still in its answer window is the full state already.
        let answering = resendSentAt.map { now - $0 < Double(oscSettings.feedbackAnswerMs) / 1000 } ?? false
        lastFeedbackAt = now
        resendSentAt = nil
        status.feedback = .live
        guard wasStale else { return }
        log.log("Syndicate feedback is back")
        for bridge in bridges { bridge.start() }
        if !answering { requestResend() }
    }

    private func checkLiveness() {
        let now = clock.now
        if let last = lastFeedbackAt, resendSentAt == nil, now - last >= Double(oscSettings.feedbackQuietMs) / 1000 {
            requestResend()
        }
        if status.feedback == .live, let sent = resendSentAt, now - sent >= Double(oscSettings.feedbackAnswerMs) / 1000 {
            feedbackStopped()
        }
        // Not live: ask again every quiet period, so a Syndicate that comes back quietly is found.
        if status.feedback != .live, let sent = resendSentAt, now - sent >= Double(oscSettings.feedbackQuietMs) / 1000 {
            resendSentAt = nil
            requestResend()
        }
    }

    /// Syndicate didn't answer: show idle for its state until it's back.
    private func feedbackStopped() {
        let event = "Syndicate feedback stopped"
        status.feedback = .stale
        status.lastDropout = event
        log.log(event)
        for bridge in bridges { bridge.clearSyndicateState() }
    }

    /// Settings (#19): the controller drives another deck from now on. Held controls are released on the old one,
    /// then the controller resyncs.
    public func setDeck(_ deck: Int, controller index: Int) {
        guard controllers.indices.contains(index), controllers[index].bridge.mapping.deck.number != deck else { return }
        controllers[index].bridge.switchDeck(to: deck)
        status.controllers[index].deck = deck
        requestResend()
        disconnectFailedOutputs()
    }

    /// Settings (#19): the controller uses these devices from now on, or nil for automatic. Held controls are
    /// released and the old ports closed first, then the controller connects and resyncs.
    public func setDevices(input: MIDIEndpoint?, output: MIDIEndpoint?, controller index: Int) {
        guard controllers.indices.contains(index) else { return }
        controllers[index].chosenInput = input?.id
        controllers[index].chosenOutput = output?.id
        controllers[index].knownSourceID = input?.id
        disconnect(index)
        if connect(index) {
            controllers[index].bridge.start()
            requestResend()
        }
        disconnectFailedOutputs()
    }

    /// Settings (#25): the controller entries, one per controller. Existing controllers take their entry's changes;
    /// new entries connect and resync.
    public func setControllers(_ entries: [ControllerSettings]) {
        // At least one controller always runs, so start() and the status have someone to show.
        guard !entries.isEmpty else { return }
        while controllers.count > entries.count { removeLastController() }
        for index in entries.indices {
            if index < controllers.count {
                update(index, to: entries[index])
            } else {
                addController(entries[index])
            }
        }
    }

    // Kept as separate small functions: Xcode 26.6's optimizer crashed (CopyPropagation) on one loop doing all three.

    private func removeLastController() {
        let last = controllers.count - 1
        controllers[last].bridge.releaseAll()
        disconnect(last)
        controllers.removeLast()
        status.controllers.removeLast()
    }

    private func addController(_ entry: ControllerSettings) {
        let first = profiles[0]
        let index = controllers.count
        status.controllers.append(ControllerStatus(deck: entry.deck, connected: false))
        var controller = Controller(bridge: Bridge(mapping: first.mapping, osc: osc, clock: clock), profile: first)
        controller.channel = entry.channel
        controllers.append(controller)
        controllers[index].bridge = makeBridge(first, for: index)
        setDevices(input: entry.input, output: entry.output, controller: index)
    }

    private func update(_ index: Int, to entry: ControllerSettings) {
        setDeck(entry.deck, controller: index)
        if entry.channel != controllers[index].channel {
            controllers[index].channel = entry.channel
            setChannel(index)
        }
        let devicesChanged = entry.input?.id != controllers[index].chosenInput || entry.output?.id != controllers[index].chosenOutput
        if devicesChanged { setDevices(input: entry.input, output: entry.output, controller: index) }
    }

    /// Rebuilds the controller's Bridge on its new channel: held controls are released first, the ports stay open.
    private func setChannel(_ index: Int) {
        let old = controllers[index].bridge
        old.releaseAll()
        let bridge = makeBridge(controllers[index].profile, for: index)
        bridge.output = old.output
        controllers[index].bridge = bridge
        guard controllers[index].source != nil else { return }
        bridge.start()
        requestResend()
    }

    /// A Bridge running `profile` with this controller's settings: its deck, channel and the LEDs switch.
    private func makeBridge(_ profile: ControllerProfile, for index: Int) -> Bridge {
        var mapping = profile.mapping
        // The deck and channel are settings, not part of the profile.
        mapping.deck.number = status.controllers[index].deck
        if let channel = controllers[index].channel { mapping.midi.channel = channel }
        let bridge = Bridge(mapping: mapping, osc: osc, clock: clock)
        bridge.setLEDsEnabled(ledsEnabled)
        return bridge
    }

    /// Settings (#19): the LEDs switch, for every controller.
    public func setLEDs(enabled: Bool) {
        ledsEnabled = enabled
        for bridge in bridges { bridge.setLEDsEnabled(enabled) }
        disconnectFailedOutputs()
    }

    /// The one place a Resend is sent. One already waiting for its answer isn't sent again.
    private func requestResend() {
        guard resendSentAt == nil else { return }
        resendSentAt = clock.now
        controllers[0].bridge.send("Feedback/Resend", .int(1))
    }

    // MARK: LED sweep (#26)

    /// Starts the LED sweep on the first controller, `delay` seconds per color (0.6, as the Python led-sweep).
    public func startLEDSweep(delay: Double = 0.6) {
        let bridge = controllers[0].bridge
        guard bridge.output != nil else {
            diagnostics?(.sweep("No controller output is open, so there is nothing to sweep."))
            return
        }
        bridge.ledsHeld = true
        sweep = (clock.now, LEDSweep.steps(for: bridge.mapping, delay: delay), 0)
        status.sweeping = true
        runSweep()
    }

    /// Whether an LED sweep is running.
    public var isSweeping: Bool { sweep != nil }

    /// Stops the sweep part-way. Its remaining steps are dropped, and the LEDs repaint.
    public func stopLEDSweep() {
        guard sweep != nil else { return }
        sweep = nil
        diagnostics?(.sweep("LED sweep stopped."))
        endSweep()
    }

    /// Gives the LEDs back to the bridge, painted from its current state.
    private func endSweep() {
        status.sweeping = false
        let bridge = controllers[0].bridge
        bridge.ledsHeld = false
        bridge.repaintLEDs()
    }

    /// Sends every sweep step that is due.
    private func runSweep() {
        guard var current = sweep else { return }
        let bridge = controllers[0].bridge
        while current.next < current.steps.count, clock.now - current.start >= current.steps[current.next].at {
            let step = current.steps[current.next]
            for send in step.sends { bridge.sweepLED(send.note, send.velocity) }
            for caption in step.captions { diagnostics?(.sweep(caption)) }
            current.next += 1
        }
        if current.next < current.steps.count {
            sweep = current
        } else {
            sweep = nil
            endSweep()
        }
    }
}
