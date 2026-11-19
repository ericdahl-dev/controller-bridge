// MIDI sends off the event loop (#552). On the unit (#428), a hung LC6000 blocked a CoreMIDI send for 5.1 s, and with it
// the one task that runs everything: OSC from Syndicate, ticks, the trace. Sends now go through one serial queue, so
// the loop never waits on a port. One queue for every port keeps their order: the ring's hold goes out before a jog
// display upload starts (#422), on another port.
import Foundation

public final class MIDISendQueue: @unchecked Sendable {
    private let queue: DispatchQueue

    public init(label: String) {
        queue = DispatchQueue(label: label)
    }

    /// `inner`, its sends made on this queue, in the order they were asked for.
    public func output(_ inner: any MIDIOutput) -> any MIDIOutput {
        QueuedMIDIOutput(inner: inner, queue: self)
    }

    /// Runs `work` on the queue, after everything asked for before it.
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Waits until everything asked for so far has gone. For tests and for closing.
    public func drain() {
        queue.sync {}
    }
}

/// An output whose sends return at once. A send that fails on the queue (the destination is gone) makes the next send
/// here throw, which the Coordinator treats as an unplug, as it did a failed send before.
final class QueuedMIDIOutput: MIDIOutput, @unchecked Sendable {
    private let inner: any MIDIOutput
    private let queue: MIDISendQueue
    private let lock = NSLock()
    private var failure: (any Error)?

    init(inner: any MIDIOutput, queue: MIDISendQueue) {
        self.inner = inner
        self.queue = queue
    }

    func send(_ event: MIDIEvent) throws {
        try enqueue { try $0.send(event) }
    }

    func send(color: LEDColorMessage) throws {
        try enqueue { try $0.send(color: color) }
    }

    func close() {
        let inner = self.inner
        queue.run { inner.close() }
    }

    private func enqueue(_ send: @escaping @Sendable (any MIDIOutput) throws -> Void) throws {
        if let failure = lock.withLock({ self.failure }) { throw failure }
        let inner = self.inner
        queue.run { [weak self] in
            do { try send(inner) } catch { self?.lock.withLock { self?.failure = error } }
        }
    }
}
