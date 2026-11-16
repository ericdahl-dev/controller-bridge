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
    public var diagnostics: ((DiagnosticEvent) -> Void)?

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
    }

    /// One controller, whose profile is chosen by the name of the device that connects. Until one does, it runs the
    /// first profile. `profiles` must not be empty.
    public init(profiles: [ControllerProfile], midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        precondition(!profiles.isEmpty, "A Coordinator needs at least one controller profile")
        self.midiSystem = midi
        self.osc = osc
        self.clock = clock
        self.log = log
        self.profiles = profiles
        let first = profiles[0]
        controllers = [Controller(bridge: Bridge(mapping: first.mapping, osc: osc, clock: clock), profile: first)]
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
        midiSystem.disconnect(source: source)
        bridge.output?.close()
        bridge.output = nil
        controllers[index].source = nil
        status.controllers[index].profile = nil
        report(index, "Disconnected \(source.name)" + (reason.map { " (\($0))" } ?? ""))
    }

    /// Opens the controller's ports if a matching device is present. Returns whether its input is connected.
    private func connect(_ index: Int) -> Bool {
        let sources = midiSystem.sources
        let known = controllers[index].knownSourceID.flatMap { id in sources.first { $0.id == id } }
        let matched = sources.first { ControllerProfile.matching($0.name, in: profiles) != nil }
        guard let source = known ?? matched, let profile = ControllerProfile.matching(source.name, in: profiles) else {
            return false
        }
        if profile != controllers[index].profile {
            controllers[index].profile = profile
            controllers[index].bridge = Bridge(mapping: profile.mapping, osc: osc, clock: clock)
        }
        let bridge = controllers[index].bridge
        do {
            try midiSystem.connect(source: source)
        } catch {
            log.log("Couldn't open MIDI input \(source.name): \(error)")
            return false
        }
        controllers[index].source = source
        controllers[index].knownSourceID = source.id
        status.controllers[index].profile = profile.name
        if let destination = Self.match(midiSystem.destinations, bridge.mapping.midi.output) {
            do { bridge.output = try midiSystem.openOutput(destination: destination) } catch {
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
        feedbackArrived()
        for bridge in bridges { bridge.handle(message) }
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

    /// The one place a Resend is sent. One already waiting for its answer isn't sent again.
    private func requestResend() {
        guard resendSentAt == nil else { return }
        resendSentAt = clock.now
        controllers[0].bridge.send("Feedback/Resend", .int(1))
    }
}
