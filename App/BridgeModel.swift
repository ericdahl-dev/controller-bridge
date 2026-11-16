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
    private var osc: SwappableOSCSender?
    private let storage = UserDefaultsStorage()
    /// What Settings shows and changes (#19). Saved in user defaults.
    private(set) var settings: BridgeSettings?
    /// The profiles that ship with the app, and the ones running (with any import applied, #24).
    private var bundledProfiles: [ControllerProfile] = []
    private(set) var profiles: [ControllerProfile] = []

    init() {
        // Line-buffered stdout, so the smoke script sees the log even when it stops the app.
        setvbuf(stdout, nil, _IOLBF, 0)
        // #34 themes every window dark; force it now so it drops in without a rewrite.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
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

    /// The panel's deck picker (#66): only that controller's deck changes, through the same path as Settings, so a
    /// held control is released on the old deck first.
    func setDeck(_ deck: Int, controller index: Int) {
        guard var new = settings, new.controllers.indices.contains(index), new.controllers[index].deck != deck else { return }
        new.controllers[index].deck = deck
        // A refused change says why, under the picker, instead of doing nothing (#90).
        do {
            try apply(new)
            status.deckProblem = nil
        } catch {
            if case .invalid(let list) = error { status.deckProblem = list.joined(separator: " ") }
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

    /// Release held controls before the Mac sleeps, and re-check the devices when it wakes.
    private func observeSleep(_ producer: EventPipe.Producer) {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in producer.sleep() },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in producer.wake() },
        ]
    }

    /// The MIDI devices Settings can pick from.
    var sources: [MIDIEndpoint] { midi?.sources ?? [] }
    var destinations: [MIDIEndpoint] { midi?.destinations ?? [] }

    /// Saves `new` and puts it into effect, or throws the problems and changes nothing. Deck and device changes go
    /// through the pipe, so the Coordinator releases held controls first.
    /// Returns a note when the settings were saved but can't take effect until a restart.
    @discardableResult
    func apply(_ new: BridgeSettings) throws(SettingsError) -> String? {
        var new = new
        new.syndicateHost = new.syndicateHost.trimmingCharacters(in: .whitespaces)
        guard let old = settings, let producer, let osc else {
            // Not running, such as a Syndicate host the sender couldn't open (#88): save valid settings anyway, so a
            // fixed host is used at the next launch. Never a silent success (#62): say a restart is needed.
            guard settings != nil else {
                throw .invalid(["The bridge isn't running, so settings can't be applied. Quit and reopen it."])
            }
            try new.save(to: storage)
            settings = new
            return "Saved. Quit and reopen the bridge to use these settings."
        }
        let problems = new.problems
        guard problems.isEmpty else { throw .invalid(problems) }
        if new.syndicateHost != old.syndicateHost || new.syndicatePort != old.syndicatePort {
            do { try osc.change(host: new.syndicateHost, port: new.syndicatePort) } catch {
                throw .invalid(["Couldn't send OSC to \(new.syndicateHost):\(new.syndicatePort): \(error)"])
            }
        }
        try new.save(to: storage)
        settings = new
        if new.controllers != old.controllers {
            producer.setControllers(new.controllers)
            status.deck = new.controllers[0].deck
        }
        status.oscPort = new.syndicatePort
        if new.ledsEnabled != old.ledsEnabled { producer.setLEDs(enabled: new.ledsEnabled) }
        if new.feedbackPort != old.feedbackPort || new.feedbackListen != old.feedbackListen { listen(new) }
        return nil
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
        let (profiles, importProblems) = MappingStore.profiles(bundled: bundled)
        bundledProfiles = bundled
        self.profiles = profiles
        status.mappingInUse = MappingStore.hasImport && importProblems.isEmpty ? "Imported: \(profiles[0].name)" : "Bundled default"
        if !importProblems.isEmpty {
            log.log("The saved mapping import was ignored: " + importProblems.joined(separator: "; "))
        }
        let mapping = profiles[0].mapping
        let settings = BridgeSettings.load(from: storage, defaults: .defaults(from: mapping))
        self.settings = settings
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

        let osc: SwappableOSCSender
        do { osc = try SwappableOSCSender(host: settings.syndicateHost, port: settings.syndicatePort) } catch {
            status.problem = "Couldn't open the OSC sender: \(error)"
            status.stopReason = .oscSender
            log.log(status.problem!)
            return
        }

        self.osc = osc
        producer = pipe.producer
        listen(settings)

        ticker = Ticker(producer: pipe.producer)
        observeSleep(pipe.producer)
        let midi = midi!
        engine = Task.detached(name: "Bridge engine") {
            await BridgeHost.run(
                profiles: profiles, midi: midi, osc: osc, log: log, status: status, diagnostics: diagnostics, events: pipe.events
            )
        }
        // The saved controller settings, queued behind the Coordinator's start.
        if settings.controllers != BridgeSettings.defaults(from: mapping).controllers {
            pipe.producer.setControllers(settings.controllers)
        }
        if !settings.ledsEnabled { pipe.producer.setLEDs(enabled: false) }
    }

    // MARK: Mapping import, export and reset (#24)

    /// Checks the file and, if it passes, saves a copy and runs it: held controls are released and the controller
    /// resyncs. Returns every problem; on any problem nothing changes and the old mapping keeps running.
    func importMapping(from url: URL) -> [String] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return ["Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"] }
        guard let active = profiles.first else { return ["The bridge didn't start, so there is no mapping to change."] }
        let imported: ControllerProfile
        do {
            imported = try ControllerProfile.importing(data, bundled: bundledProfiles, active: active.id)
        } catch MappingError.invalid(let problems) {
            return problems
        } catch {
            return ["\(error)"]
        }
        do { try MappingStore.save(data) } catch { return ["Couldn't save the mapping: \(error.localizedDescription)"] }
        profiles = MappingStore.replacing(imported, in: bundledProfiles)
        status.mappingInUse = "Imported: \(imported.name)"
        producer?.setProfiles(profiles)
        lastImportNote = ControllerProfile.importNote(
            file: url.lastPathComponent, settingsOwned: ControllerProfile.settingsOwnedKeys(in: data)
        )
        return []
    }

    /// What Settings says after the last good import: that Settings owns Deck, Channel and OSC (#93).
    private(set) var lastImportNote: String?

    /// Writes the running profile, whole, so it can be edited and imported again.
    func exportMapping(to url: URL) throws {
        guard let active = profiles.first else { return }
        try active.exported().write(to: url, options: .atomic)
    }

    /// Back to the bundled profiles; the saved import is deleted.
    func resetMapping() {
        MappingStore.remove()
        profiles = bundledProfiles
        status.mappingInUse = "Bundled default"
        producer?.setProfiles(bundledProfiles)
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
