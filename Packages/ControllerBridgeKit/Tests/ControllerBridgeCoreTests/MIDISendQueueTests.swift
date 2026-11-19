import Foundation
@testable import ControllerBridgeCore
import Testing

/// MIDI sends leave the event loop (#552): on the unit, a hung LC6000 blocked a send for 5.1 s and with it everything
/// else, OSC from Syndicate included. Sends go through one serial queue, in order, and return at once.
@Suite("MIDI send queue")
struct MIDISendQueueTests {
    /// An output whose sends block until `release` is signalled, recording what got through in order.
    final class BlockingOutput: MIDIOutput, @unchecked Sendable {
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var _sent: [String] = []
        var blocking = true
        var sent: [String] { lock.withLock { _sent } }
        func send(_ event: MIDIEvent) throws {
            if lock.withLock({ blocking }) { gate.wait() }
            lock.withLock { _sent.append("\(event)") }
        }
        func send(color: LEDColorMessage) throws {
            if lock.withLock({ blocking }) { gate.wait() }
            lock.withLock { _sent.append("color \(color.note)") }
        }
        func close() {}
        func release() {
            lock.withLock { blocking = false }
            for _ in 0..<64 { gate.signal() }
        }
    }

    @Test("A send returns at once while the output blocks; once it unblocks, everything goes out in order")
    func nonBlocking() throws {
        let inner = BlockingOutput()
        let queue = MIDISendQueue(label: "test")
        let output = queue.output(inner)
        let started = Date()
        for note in 0..<5 { try output.send(.noteOn(channel: 0, note: UInt8(note), velocity: 1)) }
        #expect(Date().timeIntervalSince(started) < 0.2)
        inner.release()
        queue.drain()
        #expect(inner.sent == (0..<5).map { "\(MIDIEvent.noteOn(channel: 0, note: UInt8($0), velocity: 1))" })
    }
}
