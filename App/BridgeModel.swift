import AppKit
import ControllerBridgeCore
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
    /// An LED sweep is running (#26).
    var sweeping = false
    var feedback: Feedback = .starting
    var problem: String?

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

    init() {
        // Line-buffered stdout, so the smoke script sees the log even when it stops the app.
        setvbuf(stdout, nil, _IOLBF, 0)
        // #34 themes every window dark; force it now so it drops in without a rewrite.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        start()
        AppDelegate.model = self
    }

    /// Quit: release everything held in Syndicate, then call `done`. Calls it after one second at the latest, so a
    /// stuck engine can't stop the app from quitting.
    /// The Diagnostics window opened or closed: only while it's open does the engine build anything for it.
    func setDiagnostics(open: Bool) { producer?.diagnostics(open: open) }
    func startLEDSweep(delay: Double) { producer?.ledSweep(delay: delay) }
    func cancelLEDSweep() { producer?.cancelLEDSweep() }

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
    func apply(_ new: BridgeSettings) throws(SettingsError) {
        guard let old = settings, let producer, let osc else { return }
        let problems = new.problems
        guard problems.isEmpty else { throw .invalid(problems) }
        if new.syndicateHost != old.syndicateHost || new.syndicatePort != old.syndicatePort {
            do { try osc.change(host: new.syndicateHost, port: new.syndicatePort) } catch {
                throw .invalid(["Couldn't send OSC to \(new.syndicateHost):\(new.syndicatePort): \(error)"])
            }
        }
        try new.save(to: storage)
        settings = new
        let was = old.controllers[0], now = new.controllers[0]
        if now.deck != was.deck {
            producer.setDeck(now.deck, controller: 0)
            status.deck = now.deck
        }
        if now.input != was.input || now.output != was.output {
            producer.setDevices(input: now.input, output: now.output, controller: 0)
        }
        if new.ledsEnabled != old.ledsEnabled { producer.setLEDs(enabled: new.ledsEnabled) }
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
        let profiles: [ControllerProfile]
        do { profiles = try ControllerProfile.bundled() } catch {
            status.problem = "Couldn't load the controller profiles: \(error)"
            return
        }
        let mapping = profiles[0].mapping
        let settings = BridgeSettings.load(from: storage, defaults: .defaults(from: mapping))
        self.settings = settings
        status.deck = settings.controllers[0].deck
        let pipe = EventPipe()
        let status = status
        let diagnostics = diagnostics

        do {
            midi = try CoreMIDISystem(producer: pipe.producer) { names in
                Task { @MainActor in status.controllers = names.sorted() }
            }
        } catch {
            status.problem = "Couldn't start CoreMIDI: \(error)"
            log.log(status.problem!)
            return
        }

        let osc: SwappableOSCSender
        do { osc = try SwappableOSCSender(host: settings.syndicateHost, port: settings.syndicatePort) } catch {
            status.problem = "Couldn't open the OSC sender: \(error)"
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
        let controller = settings.controllers[0]
        if controller.deck != mapping.deck.number { pipe.producer.setDeck(controller.deck, controller: 0) }
        if controller.input != nil || controller.output != nil {
            pipe.producer.setDevices(input: controller.input, output: controller.output, controller: 0)
        }
        if !settings.ledsEnabled { pipe.producer.setLEDs(enabled: false) }
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
