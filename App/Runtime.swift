// Wires the adapters to the Kit. Not unit-tested: the Engine and Coordinator are tested in ControllerBridgeKit, the rest by
// the smoke script.
import Dispatch
import Foundation
import ControllerBridgeCore
import os

/// Makes the Coordinator inside one task and runs the Engine loop there, so that loop is the only code that ever
/// touches it. Anything else that must reach the Coordinator (stop, sleep, device changes) goes through the pipe,
/// which also keeps it in order with the MIDI already queued.
enum BridgeHost {
    static func run(
        profiles: [ControllerProfile], midi: any MIDISystem, osc: any OSCSender, log: any LogSink, status: BridgeStatus,
        diagnostics: DiagnosticsLog, controllers: [ControllerSettings], ledsEnabled: Bool, events: AsyncStream<PipeEvent>
    ) async {
        let coordinator = Coordinator(profiles: profiles, midi: midi, osc: osc, clock: SystemClock(), log: log)
        // Straight onto the saved devices, decks, layers and LEDs switch: nothing unchosen, even for a moment (#105).
        coordinator.start(controllers: controllers, ledsEnabled: ledsEnabled)
        // The demo controller (#64) runs the profile running now (an imported mapping too, #98) against an in-process
        // controller and an in-memory Syndicate.
        let makeDemo: @Sendable (ControllerProfile) -> DemoSession = { profile in
            DemoSession(profile: profile, clock: SystemClock(), log: log, ledOutput: DroppedMIDIOutput())
        }
        await Engine(
            coordinator: coordinator, log: log, onStatus: statusSink(status), onDiagnostic: diagnosticsSink(diagnostics),
            makeDemo: makeDemo
        ).run(events)
    }

    /// Hands each Diagnostics line to the window, one main-actor hop per line. Only called while the window is open.
    private nonisolated static func diagnosticsSink(_ log: DiagnosticsLog) -> @Sendable (DiagnosticEvent) -> Void {
        { event in Task { @MainActor in log.append(event) } }
    }

    /// Copies each Coordinator status change into the menu's status, with one main-actor hop per change. Made here,
    /// outside any actor: a closure written in main-actor code and called on the engine's task traps (#14 spike).
    private nonisolated static func statusSink(_ status: BridgeStatus) -> @Sendable (CoordinatorStatus) -> Void {
        { coordinatorStatus in
            Task { @MainActor in
                status.bridges = coordinatorStatus.controllers
                status.devices = coordinatorStatus.devices
                // Stamp the time a dropout happens, for the panel's LAST DROPOUT (#66).
                if coordinatorStatus.feedback == .stale, status.syndicateFeedback != .stale {
                    status.lastDropoutTime = Date.now.formatted(date: .omitted, time: .shortened)
                }
                status.syndicateFeedback = coordinatorStatus.feedback
                status.noDeckData = coordinatorStatus.noDeckData
                status.missingSubscriptions = coordinatorStatus.missingSubscriptions
                status.requiredSubscriptions = coordinatorStatus.requiredSubscriptions
                status.lastDropout = coordinatorStatus.lastDropout
                status.sweeping = coordinatorStatus.sweeping
                status.demo = coordinatorStatus.demo
                status.deckColors = coordinatorStatus.deckColors
            }
        }
    }
}

/// Puts a tick into the pipe every 10 ms, for the Coordinator's timers (the jog release, #17).
final class Ticker: Sendable {
    private let timer: any DispatchSourceTimer

    init(producer: EventPipe.Producer) {
        timer = Self.makeTimer(producer)
        timer.resume()
    }

    private nonisolated static func makeTimer(_ producer: EventPipe.Producer) -> any DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dev.ericdahl.ControllerBridge.tick"))
        // Leeway lets the system batch wakeups.
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(5))
        timer.setEventHandler { producer.tick() }
        return timer
    }

    func stop() { timer.cancel() }
}

struct SystemClock: ControllerBridgeCore.Clock {
    var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
}

/// The Coordinator's log goes to the unified log (and to stdout when run from a terminal, for the smoke script).
struct UnifiedLogSink: LogSink {
    private static let logger = Logger(subsystem: "dev.ericdahl.ControllerBridge", category: "bridge")
    func log(_ line: String) {
        Self.logger.info("\(line, privacy: .public)")
        print(line)
    }
}

/// The demo controller has no LEDs to light (#64): its LED writes go nowhere.
struct DroppedMIDIOutput: MIDIOutput {
    func send(_ event: MIDIEvent) throws {}
    func close() {}
}
