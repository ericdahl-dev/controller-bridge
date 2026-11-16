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
    /// Each controller's deck, connection and last disconnect or reconnect, from the Coordinator (#20).
    var bridges: [ControllerStatus] = []
    /// Every MIDI source and the controller profile it matched (#43); one with no profile is listed, not bridged.
    var devices: [DeviceStatus] = []
    /// Whether Syndicate's feedback is arriving (#21): the listener can be up while Syndicate is quiet or gone.
    var syndicateFeedback: FeedbackState = .waiting
    /// The last time Syndicate's feedback stopped, for the menu.
    var lastDropout: String?
    var feedback: Feedback = .starting
    var problem: String?

    var isConnected: Bool {
        guard problem == nil, !controllers.isEmpty, case .listening = feedback, syndicateFeedback != .stale else { return false }
        return true
    }
}

/// Starts the bridge at launch and keeps its adapters alive.
@MainActor
final class BridgeModel {
    let status = BridgeStatus()
    private var listener: FeedbackListener?
    private var ticker: Ticker?
    private var midi: CoreMIDISystem?
    private var producer: EventPipe.Producer?
    private var engine: Task<Void, Never>?
    private var sleepObservers: [any NSObjectProtocol] = []

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
        let pipe = EventPipe()
        let status = status

        do {
            midi = try CoreMIDISystem(producer: pipe.producer) { names in
                Task { @MainActor in status.controllers = names.sorted() }
            }
        } catch {
            status.problem = "Couldn't start CoreMIDI: \(error)"
            log.log(status.problem!)
            return
        }

        let osc: UDPOSCSender
        do { osc = try UDPOSCSender(host: mapping.osc.host, port: mapping.osc.port) } catch {
            status.problem = "Couldn't open the OSC sender: \(error)"
            log.log(status.problem!)
            return
        }

        // The default is loopback (127.0.0.1), so there is no local-network prompt.
        let feedbackHost = mapping.osc.feedbackHost, feedbackPort = mapping.osc.feedbackPort
        do {
            listener = try FeedbackListener.start(host: feedbackHost, port: feedbackPort, producer: pipe.producer)
            status.feedback = .listening(port: feedbackPort)
            log.log("Feedback listening on \(feedbackHost):\(feedbackPort)")
        } catch {
            status.feedback = error.isAddressInUse ? .portInUse(port: feedbackPort) : .failed(error.description)
            log.log("Feedback listener on \(feedbackHost):\(feedbackPort) failed: \(error)")
        }

        ticker = Ticker(producer: pipe.producer)
        producer = pipe.producer
        observeSleep(pipe.producer)
        let midi = midi!
        engine = Task.detached(name: "Bridge engine") {
            await BridgeHost.run(profiles: profiles, midi: midi, osc: osc, log: log, status: status, events: pipe.events)
        }
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
