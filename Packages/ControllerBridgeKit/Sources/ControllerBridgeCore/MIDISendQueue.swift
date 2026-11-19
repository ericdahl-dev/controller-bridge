// MIDI sends off the event loop (#552). On the unit (#428), a hung LC6000 blocked a CoreMIDI send for 5.1 s, and with it
// the one task that runs everything: OSC from Syndicate, ticks, the trace. Sends now go through one serial queue, so
// the loop never waits on a port. One queue for every port keeps their order: the ring's hold goes out before a jog
// display upload starts (#422), on another port.
//
// A port whose send hasn't returned within `stuckAfter` is stuck: later sends to it are dropped, and `onStuck` says so
// once, until the port is opened again (a reconnect, #429, which repaints). The backlog is bounded: past it the oldest
// LED write is dropped (a light's state; the latest is what matters), never anything else.
import Foundation

public final class MIDISendQueue: @unchecked Sendable {
    private struct Item {
        let port: Int
        /// An LED write: state, so an old one may be dropped.
        let droppable: Bool
        let work: @Sendable () -> Void
    }

    private let worker: DispatchQueue
    private let lock = NSLock()
    private let stuckAfter: Double
    private let backlog: Int
    private let onStuck: @Sendable (String) -> Void
    private var items: [Item] = []
    private var running = false
    private var inFlight: (port: Int, since: Double)?
    private var stuck: Set<Int> = []
    private var nextPort = 0

    /// `onStuck` gets the port's name, once, when it goes stuck.
    public init(label: String, stuckAfter: Double = 0.5, backlog: Int = 512,
                onStuck: @escaping @Sendable (String) -> Void = { _ in }) {
        worker = DispatchQueue(label: label)
        self.stuckAfter = stuckAfter
        self.backlog = backlog
        self.onStuck = onStuck
    }

    /// `inner`, its sends made on this queue, in the order they were asked for. Each call is a new port: one reopened
    /// after a reconnect starts out not stuck.
    public func output(_ inner: any MIDIOutput, name: String = "") -> any MIDIOutput {
        QueuedMIDIOutput(inner: inner, queue: self, port: newPort(), name: name)
    }

    func newPort() -> Int { lock.withLock { nextPort += 1; return nextPort } }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Queues `work` for `port`, unless the port is stuck. Returns at once.
    func enqueue(port: Int, name: String, droppable: Bool, _ work: @escaping @Sendable () -> Void) {
        var newlyStuck = false
        let start: Bool = lock.withLock {
            if stuck.contains(port) { return false }
            if let flight = inFlight, flight.port == port, Self.now - flight.since >= stuckAfter {
                stuck.insert(port)
                newlyStuck = true
                items.removeAll { $0.port == port }
                return false
            }
            items.append(Item(port: port, droppable: droppable, work: work))
            if items.count > backlog, let oldest = items.firstIndex(where: \.droppable) { items.remove(at: oldest) }
            guard !running else { return false }
            running = true
            return true
        }
        if newlyStuck { onStuck(name) }
        if start { worker.async { self.run() } }
    }

    private func run() {
        while true {
            let next: Item? = lock.withLock {
                guard !items.isEmpty else {
                    running = false
                    inFlight = nil
                    return nil
                }
                let item = items.removeFirst()
                inFlight = (item.port, Self.now)
                return item
            }
            guard let next else { return }
            next.work()
        }
    }

    /// Waits until everything queued so far has gone. For tests and for closing.
    public func drain() {
        while lock.withLock({ running || !items.isEmpty }) { worker.sync {} }
    }
}

/// An output whose sends return at once. A send that fails on the queue (the destination is gone) makes the next send
/// here throw, which the Coordinator treats as an unplug, as it did a failed send before.
final class QueuedMIDIOutput: MIDIOutput, @unchecked Sendable {
    private let inner: any MIDIOutput
    private let queue: MIDISendQueue
    private let port: Int
    private let name: String
    private let lock = NSLock()
    private var failure: (any Error)?

    init(inner: any MIDIOutput, queue: MIDISendQueue, port: Int, name: String) {
        self.inner = inner
        self.queue = queue
        self.port = port
        self.name = name
    }

    func send(_ event: MIDIEvent) throws {
        try enqueue { try $0.send(event) }
    }

    func send(color: LEDColorMessage) throws {
        try enqueue { try $0.send(color: color) }
    }

    func close() {
        let inner = self.inner
        queue.enqueue(port: port, name: name, droppable: false) { inner.close() }
    }

    /// Every send here is an LED's: a note-on, a CC (a meter) or a color message.
    private func enqueue(_ send: @escaping @Sendable (any MIDIOutput) throws -> Void) throws {
        if let failure = lock.withLock({ self.failure }) { throw failure }
        let inner = self.inner
        queue.enqueue(port: port, name: name, droppable: true) { [weak self] in
            do { try send(inner) } catch { self?.lock.withLock { self?.failure = error } }
        }
    }
}
