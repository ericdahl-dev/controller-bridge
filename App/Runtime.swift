// Wires the adapters to the Kit. Not unit-tested: the Engine and Coordinator are tested in LC6000Kit, the rest by
// the smoke script.
import Dispatch
import Foundation
import LC6000Core
import os

/// Makes the Coordinator inside one task and runs the Engine loop there, so that loop is the only code that ever
/// touches it. Anything else that must reach the Coordinator (stop, sleep, device changes) goes through the pipe,
/// which also keeps it in order with the MIDI already queued.
enum BridgeHost {
    static func run(mapping: Mapping, midi: any MIDISystem, osc: any OSCSender, log: any LogSink, events: AsyncStream<PipeEvent>) async {
        let coordinator = Coordinator(mapping: mapping, midi: midi, osc: osc, clock: SystemClock(), log: log)
        coordinator.start()
        await Engine(coordinator: coordinator, log: log).run(events)
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
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dev.ericdahl.LC6000Bridge.tick"))
        // Leeway lets the system batch wakeups.
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(5))
        timer.setEventHandler { producer.tick() }
        return timer
    }

    func stop() { timer.cancel() }
}

struct SystemClock: LC6000Core.Clock {
    var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
}

/// The Coordinator's log goes to the unified log (and to stdout when run from a terminal, for the smoke script).
struct UnifiedLogSink: LogSink {
    private static let logger = Logger(subsystem: "dev.ericdahl.LC6000Bridge", category: "bridge")
    func log(_ line: String) {
        Self.logger.info("\(line, privacy: .public)")
        print(line)
    }
}
