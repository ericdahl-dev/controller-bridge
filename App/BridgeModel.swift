import AppKit
import LC6000Core
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
    private var listener: FeedbackListener?
    private var ticker: Ticker?
    private var midi: CoreMIDISystem?

    init() {
        // Line-buffered stdout, so the smoke script sees the log even when it stops the app.
        setvbuf(stdout, nil, _IOLBF, 0)
        // #34 themes every window dark; force it now so it drops in without a rewrite.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        start()
    }

    private func start() {
        let log = UnifiedLogSink()
        let mapping: Mapping
        do { mapping = try Mapping.bundledDefault() } catch {
            status.problem = "Couldn't load the mapping: \(error)"
            return
        }
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
        let midi = midi!
        Task.detached(name: "Bridge engine") { await BridgeHost.run(mapping: mapping, midi: midi, osc: osc, log: log, events: pipe.events) }
    }
}
