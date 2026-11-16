/// The one consumer of an EventPipe: it feeds each event to the Coordinator, in order, on one task.
///
/// No Task per message. The app runs `run(_:)` once, on whatever single executor owns the Coordinator.
public struct Engine {
    private let coordinator: Coordinator
    private let log: any LogSink

    public init(coordinator: Coordinator, log: any LogSink) {
        self.coordinator = coordinator
        self.log = log
    }

    /// Returns when the pipe finishes.
    public func run(_ events: AsyncStream<PipeEvent>) async {
        for await event in events {
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
            }
        }
    }
}
