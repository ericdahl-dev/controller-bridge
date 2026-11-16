/// The one consumer of an EventPipe: it feeds each event to the Coordinator, in order, on one task.
///
/// No Task per message. The app runs `run(_:)` once, on whatever single executor owns the Coordinator.
public struct Engine {
    private let coordinator: Coordinator
    private let log: any LogSink
    private let onDiagnostic: (@Sendable (DiagnosticEvent) -> Void)?
    private let onStatus: (@Sendable (CoordinatorStatus) -> Void)?

    /// `onStatus` gets the Coordinator's status when the loop starts and again each time it changes, on the loop's
    /// task. The app hops it to the main actor once per change.
    public init(
        coordinator: Coordinator, log: any LogSink, onStatus: (@Sendable (CoordinatorStatus) -> Void)? = nil,
        onDiagnostic: (@Sendable (DiagnosticEvent) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.log = log
        self.onStatus = onStatus
        self.onDiagnostic = onDiagnostic
    }

    /// Returns when the pipe finishes, or right after a stop.
    public func run(_ events: AsyncStream<PipeEvent>) async {
        var reported = coordinator.status
        onStatus?(reported)
        for await event in events {
            defer {
                if coordinator.status != reported {
                    reported = coordinator.status
                    onStatus?(reported)
                }
            }
            switch event {
            case .midi(let midi, let source): coordinator.midi(midi, source: source)
            case .udp(let datagram):
                do {
                    for message in try OSCPacket(decoding: datagram).messages { coordinator.feedback(message) }
                } catch {
                    log.log("Dropped a feedback datagram (\(datagram.count) bytes): \(error)")
                }
            case .tick: coordinator.tick()
            case .devicesChanged: coordinator.devicesChanged()
            case .sleep: coordinator.willSleep()
            case .wake: coordinator.didWake()
            // Only while the window is open does the Coordinator build anything for it.
            case .diagnostics(let open):
                if open, let sink = onDiagnostic { coordinator.diagnostics = { sink($0) } } else { coordinator.diagnostics = nil }
            case .ledSweep(let delay): coordinator.startLEDSweep(delay: delay)
            case .cancelLEDSweep: coordinator.cancelLEDSweep()
            case .setDeck(let deck, let controller): coordinator.setDeck(deck, controller: controller)
            case .setDevices(let input, let output, let controller):
                coordinator.setDevices(input: input, output: output, controller: controller)
            case .setLEDs(let enabled): coordinator.setLEDs(enabled: enabled)
            case .stop:
                // Releases are sent synchronously, so they have all gone out once run() returns.
                coordinator.stop()
                return
            }
        }
    }
}
