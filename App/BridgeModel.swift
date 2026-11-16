import AppKit
import ControllerBridgeCore
import ControllerBridgePresentation
import Observation

/// What the menu shows. A main-actor copy: the adapters report into it, and nothing reads the Coordinator from here.
@MainActor @Observable
final class BridgeStatus {
    enum Feedback: Equatable {
        case starting
        case listening(port: Int)
        case portInUse(port: Int)
        case failed(String)
    }

    var controllers: [String] = []
    /// The Syndicate deck this controller drives.
    var deck = 1
    /// Each controller's deck, connection and last disconnect or reconnect, from the Coordinator (#20).
    var bridges: [ControllerStatus] = []
    /// Every MIDI source and the controller profile it matched (#43); one with no profile is listed, not bridged.
    var devices: [DeviceStatus] = []
    /// Whether Syndicate's feedback is arriving (#21): the listener can be up while Syndicate is quiet or gone.
    var syndicateFeedback: FeedbackState = .waiting
    /// Syndicate answers with no deck info: its OSC FEEDBACK subscriptions are off (#150).
    var noDeckData = false
    /// LED subscriptions a loaded deck's answer lacked (#150).
    var missingSubscriptions: [Subscription] = []
    /// What the controllers' profiles need, for the setup guide (#211).
    var requiredSubscriptions: [Subscription] = Subscription.allCases
    /// The last time Syndicate's feedback stopped, for the menu.
    var lastDropout: String?
    /// When feedback last dropped, as the time to show ("21:14"), stamped as it happens (#66).
    var lastDropoutTime: String?
    /// The Syndicate OSC port in use, from settings (#66), for the panel's ports line.
    var oscPort = 9090
    /// Which part couldn't start, when `problem` is set (#88).
    var stopReason: BridgeState.StopReason = .midi
    /// Why the last deck change was refused, if it was (#90).
    var deckProblem: String?
    /// An LED sweep is running (#26).
    var sweeping = false
    /// The deck colors in use, for the badges (#123).
    var deckColors = DeckColors.defaults
    /// The built-in demo controller is running (#64). Off at launch and never saved.
    var demo = false
    var feedback: Feedback = .starting
    var problem: String?
    /// The running mapping (#24): the bundled profile's name, or that an imported file is in use.
    var mappingInUse = "Bundled default"

    var isConnected: Bool {
        guard problem == nil, !controllers.isEmpty, case .listening = feedback else { return false }
        return true
    }
}

/// Starts the bridge at launch and keeps its adapters alive.
@MainActor
final class BridgeModel {
    let status = BridgeStatus()
    /// What the Diagnostics window shows (#26).
    let diagnostics = DiagnosticsLog()
    private var listener: FeedbackListener?
    private var ticker: Ticker?
    private var midi: CoreMIDISystem?
    private var producer: EventPipe.Producer?
    private var engine: Task<Void, Never>?
    private var sleepObservers: [any NSObjectProtocol] = []
    private var osc: OSCDestination?
    private let storage = UserDefaultsStorage()
    /// What Settings shows and changes (#19). Saved in user defaults.
    /// The running profile's deck layers (#79): empty for a controller without them.
    private(set) var layers: [Mapping.Layer] = []
    private(set) var settings: BridgeSettings?
    /// Puts settings into effect (#136): everything but the host at once, the host when it opens.
    private var applier: SettingsApplier?
    /// The profiles that ship with the app, and the ones running with any import applied (#24). The decisions are
    /// in ControllerBridgeCore's MappingLibrary (#94); this keeps the file.
    private var library: MappingLibrary?
    var profiles: [ControllerProfile] { library?.profiles ?? [] }
    /// What Settings says after the last good import: that Settings owns Deck, Channel and OSC (#93).
    var lastImportNote: String? { library?.importNote }

    init() {
        // Line-buffered stdout, so the smoke script sees the log even when it stops the app.
        setvbuf(stdout, nil, _IOLBF, 0)
        start()
        AppDelegate.model = self
    }

    #if DEBUG
    /// Snapshots only (#68): settings to show, with no bridge, MIDI or network started. Nil shows the stopped state.
    init(preview settings: BridgeSettings?) {
        self.settings = settings
    }
    #endif

    /// Quit: release everything held in Syndicate, then call `done`. Calls it after one second at the latest, so a
    /// stuck engine can't stop the app from quitting.
    /// The Diagnostics window opened or closed: only while it's open does the engine build anything for it.
    func setDiagnostics(open: Bool) { producer?.diagnostics(open: open) }
    func startLEDSweep(delay: Double) { producer?.ledSweep(delay: delay) }
    func stopLEDSweep() { producer?.stopLEDSweep() }
    /// Turns the demo controller (#64) on or off. In memory only: it is off again at the next launch.
    func setDemo(_ on: Bool) { producer?.demo(on: on) }
    /// Pauses (a source) or gives back (nil) a controller while the capture window records it (#186).
    func setCapture(source: MIDIEndpoint.ID?) { producer?.setCapture(source: source) }

    /// The panel's deck picker (#66): only that controller's deck changes, through the same path as Settings, so a
    /// held control is released on the old deck first.
    func setDeck(_ deck: Int, controller index: Int) {
        guard var new = settings, new.controllers.indices.contains(index), new.controllers[index].deck != deck else { return }
        new.controllers[index].deck = deck
        // At once, never waiting on the network (#136). A refused change says why, under the picker (#90).
        guard let applier else {
            status.deckProblem = "The bridge isn't running, so the deck can't change. Quit and reopen it."
            return
        }
        do {
            try applier.applyNow(new)
            status.deckProblem = nil
        } catch {
            switch error {
            case .invalid(let list): status.deckProblem = list.joined(separator: " ")
            case .fields(let list): status.deckProblem = list.map(\.message).joined(separator: " ")
            }
        }
    }

    func quit(_ done: @escaping @MainActor () -> Void) {
        guard let producer, let engine else { return done() }
        var finished = false
        let finish = { if !finished { finished = true; done() } }
        producer.stop()
        Task { @MainActor in
            await engine.value
            finish()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            finish()
        }
    }

    /// Opens Syndicate's host in the background (#84, #109): the status shows a failure until it's fixed.
    private func connectOSC(host: String, port: Int) {
        guard let osc else { return }
        let status = status, log = UnifiedLogSink()
        Task { @MainActor in
            if let problem = await osc.connect(host: host, port: port) {
                status.problem = problem
                status.stopReason = .oscSender
                log.log(problem)
            } else if status.stopReason == .oscSender, osc.isReady, osc.lastError == nil {
                // Nil can also mean a newer connect overtook this one (#135): clear only once a destination is open.
                status.problem = nil
            }
        }
    }

    /// Release held controls before the Mac sleeps, and re-check the devices when it wakes.
    private func observeSleep(_ producer: EventPipe.Producer) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in producer.sleep() },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                producer.wake()
                // A `.local` host may have a new address after sleep (#84).
                Task { @MainActor in await self?.osc?.reresolve() }
            },
        ]
    }

    /// The MIDI devices Settings can pick from.
    var sources: [MIDIEndpoint] { midi?.sources ?? [] }
    var destinations: [MIDIEndpoint] { midi?.destinations ?? [] }

    /// Saves `new` and puts it into effect, or throws the problems and changes nothing. Deck and device changes go
    /// through the pipe, so the Coordinator releases held controls first.
    /// Returns a note when the settings were saved but can't take effect until a restart.
    /// Async: a host name is looked up off the main actor first (#84), and Settings stays usable meanwhile.
    @discardableResult
    func apply(_ new: BridgeSettings) async throws(SettingsError) -> String? {
        var new = new
        new.syndicateHost = new.syndicateHost.trimmingCharacters(in: .whitespaces)
        guard settings != nil, producer != nil, let osc, let applier else {
            // Not running, such as a Syndicate host the sender couldn't open (#88): save valid settings anyway, so a
            // fixed host is used at the next launch. Never a silent success (#62): say a restart is needed.
            guard settings != nil else {
                throw .invalid(["The bridge isn't running, so settings can't be applied. Quit and reopen it."])
            }
            try new.save(to: storage)
            settings = new
            return "Saved. Quit and reopen the bridge to use these settings."
        }
        // Everything but the host applies at once; a new host opens after, and a failure goes under its field (#136).
        try await applier.apply(new, senderReady: osc.isReady)
        if osc.isReady, status.stopReason == .oscSender { status.problem = nil }
        return nil
    }

    /// One applied change, from the applier: tell the Coordinator and update the status.
    private func putIntoEffect(old: BridgeSettings, new: BridgeSettings) {
        settings = new
        guard let producer else { return }
        if new.controllers != old.controllers {
            // A controller following its own layers runs as one entry per layer (#79).
            producer.setControllers(ControllerSettings.expanded(new.controllers, layers: layers))
            status.deck = new.controllers[0].deck
        }
        status.oscPort = new.syndicatePort
        if new.ledsEnabled != old.ledsEnabled { producer.setLEDs(enabled: new.ledsEnabled) }
        if new.appearance != old.appearance { NSApplication.shared.appearance = new.appearance.nsAppearance }
        if new.followSyndicateDeckColors != old.followSyndicateDeckColors || new.customDeckColors != old.customDeckColors {
            producer.setDeckColors(followSyndicate: new.followSyndicateDeckColors, custom: new.customDeckColors)
        }
        if new.ringColors != old.ringColors { producer.setRingColors(new.ringColors) }
        if new.feedbackPort != old.feedbackPort || new.feedbackListen != old.feedbackListen { listen(new) }
    }

    /// (Re)binds the feedback listener. The old one is closed first; a failure shows in the status, never crashes.
    private func listen(_ settings: BridgeSettings) {
        guard let producer else { return }
        listener?.stop()
        listener = nil
        let log = UnifiedLogSink()
        let host = settings.feedbackListen.address, port = settings.feedbackPort
        do {
            listener = try FeedbackListener.start(host: host, port: port, producer: producer)
            status.feedback = .listening(port: port)
            log.log("Feedback listening on \(host):\(port)")
        } catch {
            status.feedback = error.isAddressInUse ? .portInUse(port: port) : .failed(error.description)
            log.log("Feedback listener on \(host):\(port) failed: \(error)")
        }
    }

    private func start() {
        let log = UnifiedLogSink()
        // Each connected device gets the profile its name matches (#43). The OSC settings come from the first
        // profile's mapping until Settings (#19) holds them.
        let bundled: [ControllerProfile]
        do { bundled = try ControllerProfile.bundled() } catch {
            status.problem = "Couldn't load the controller profiles: \(error)"
            status.stopReason = .profiles
            return
        }
        // A saved import (#24) applies at launch; one that no longer passes the check is set aside, and says why.
        let library = MappingLibrary(bundled: bundled, saved: MappingStore.saved)
        self.library = library
        let profiles = library.profiles
        status.mappingInUse = library.inUse
        if !library.launchProblems.isEmpty {
            log.log("The saved mapping import was ignored: " + library.launchProblems.joined(separator: "; "))
        }
        let mapping = profiles[0].mapping
        layers = mapping.midi.layers
        let settings = BridgeSettings.load(from: storage, defaults: .defaults(from: mapping))
        self.settings = settings
        NSApplication.shared.appearance = settings.appearance.nsAppearance
        status.deck = settings.controllers[0].deck
        status.oscPort = settings.syndicatePort
        let pipe = EventPipe()
        let status = status
        let diagnostics = diagnostics

        do {
            midi = try CoreMIDISystem(producer: pipe.producer) { names in
                Task { @MainActor in status.controllers = names.sorted() }
            }
        } catch {
            status.problem = "Couldn't start CoreMIDI: \(error)"
            status.stopReason = .midi
            log.log(status.problem!)
            return
        }

        // Syndicate's host, by address or by name (#84). Launch never waits on it: the bridge starts now, and sends
        // begin once the host opens. Until then, or if it can't (#109), the status says so and Apply fixes it.
        let osc = OSCDestination(
            resolver: SystemHostResolver(), open: { ip, port in try UDPSink(ipv4: ip, port: port) }, clock: SystemClock()
        )
        let resyncProducer = pipe.producer
        osc.onReady = { resyncProducer.resync() }
        osc.onSendFailure = { [weak osc] in Task { await osc?.reresolve() } }
        self.osc = osc
        connectOSC(host: settings.syndicateHost, port: settings.syndicatePort)
        producer = pipe.producer
        applier = SettingsApplier(
            settings: settings, storage: storage, connect: { [osc] host, port in await osc.connect(host: host, port: port) }
        ) { [weak self] old, new in self?.putIntoEffect(old: old, new: new) }
        listen(settings)

        ticker = Ticker(producer: pipe.producer)
        observeSleep(pipe.producer)
        let midi = midi!
        // The entries the Coordinator starts with: the saved ones, a controller following its layers as one per layer
        // (#79). It starts straight on them (#105), so nothing is sent after start to correct it.
        let running = ControllerSettings.expanded(settings.controllers, layers: layers)
        engine = Task.detached(name: "Bridge engine") {
            await BridgeHost.run(
                profiles: profiles, midi: midi, osc: osc, log: log, status: status, diagnostics: diagnostics,
                controllers: running, ledsEnabled: settings.ledsEnabled, events: pipe.events
            )
        }
        // The saved deck colors (#123), queued behind the Coordinator's start.
        pipe.producer.setDeckColors(followSyndicate: settings.followSyndicateDeckColors, custom: settings.customDeckColors)
        pipe.producer.setRingColors(settings.ringColors)

    }

    // MARK: Mapping import, export and reset (#24)

    /// Checks the file and, if it passes, saves a copy and runs it: held controls are released and the controller
    /// resyncs. Returns every problem; on any problem nothing changes and the old mapping keeps running.
    func importMapping(from url: URL) -> [String] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return ["Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"] }
        guard var next = library else { return ["The bridge didn't start, so there is no mapping to change."] }
        let problems = next.importFile(data, named: url.lastPathComponent)
        guard problems.isEmpty else { return problems }
        // Saved before it runs, so what runs is what comes back at the next launch.
        do { try MappingStore.save(data) } catch { return ["Couldn't save the mapping: \(error.localizedDescription)"] }
        library = next
        status.mappingInUse = next.inUse
        producer?.setProfiles(next.profiles)
        return []
    }

    /// Writes the running profile, whole, so it can be edited and imported again.
    func exportMapping(to url: URL) throws {
        guard let active = profiles.first else { return }
        try active.exported().write(to: url, options: .atomic)
    }

    /// Back to the bundled profiles; the saved import is deleted. Returns a problem if it couldn't be, and then
    /// nothing changes, so the import doesn't quietly come back at the next launch.
    func resetMapping() -> String? {
        guard var next = library else { return nil }
        do { try MappingStore.remove() } catch { return "Couldn't remove the imported mapping: \(error.localizedDescription)" }
        next.reset()
        library = next
        status.mappingInUse = next.inUse
        producer?.setProfiles(next.profiles)
        return nil
    }
}

/// Holds quitting until the release sends have gone out (#20), for the menu's Quit button and for Command-Q alike: both
/// go through `NSApplication.terminate`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: BridgeModel?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model else { return .terminateNow }
        model.quit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
