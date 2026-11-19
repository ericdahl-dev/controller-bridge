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

    /// The rig's MIDI system, its outputs through a send queue over an output that blocks.
    final class QueuedMIDISystem: MIDISystem, @unchecked Sendable {
        let inner = Rig.FakeMIDISystem(sources: [Rig.lc6000], destinations: [Rig.lc6000Out])
        let queue = MIDISendQueue(label: "test")
        let blocking = BlockingOutput()
        var sources: [MIDIEndpoint] { inner.sources }
        var destinations: [MIDIEndpoint] { inner.destinations }
        func connect(source: MIDIEndpoint) throws { try inner.connect(source: source) }
        func disconnect(source: MIDIEndpoint) { inner.disconnect(source: source) }
        func openOutput(destination: MIDIEndpoint) throws -> any MIDIOutput { queue.output(blocking) }
    }

    @Test("While the controller's port blocks, Syndicate's feedback is still handled at once; the LEDs follow once it unblocks")
    func feedbackWhileBlocked() throws {
        let midi = QueuedMIDISystem()
        let osc = Rig.FakeOSC()
        let coordinator = Coordinator(mapping: try Mapping.bundledDefault(), midi: midi, osc: osc, clock: Rig.FakeClock(),
                                      log: Rig.FakeLog())
        let started = Date()
        coordinator.start()                                       // paints every LED: all of it waits on the port
        coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)   // Play
        #expect(Date().timeIntervalSince(started) < 0.5)
        #expect(osc.sent.contains(OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])))
        midi.blocking.release()
        midi.queue.drain()
        #expect(midi.blocking.sent.last { $0.contains("note: 1,") } == "\(MIDIEvent.noteOn(channel: 0, note: 1, velocity: 127))")
    }

    @Test("A port whose send hasn't returned within the bound is stuck: later sends to it are dropped, and said once")
    func stuck() throws {
        let inner = BlockingOutput()
        final class Notices: @unchecked Sendable {
            let lock = NSLock()
            var names: [String] = []
        }
        let notices = Notices()
        let queue = MIDISendQueue(label: "test", stuckAfter: 0.05) { name in notices.lock.withLock { notices.names.append(name) } }
        let output = queue.output(inner, name: "LC6000")
        try output.send(.noteOn(channel: 0, note: 1, velocity: 1))   // in flight, blocked
        Thread.sleep(forTimeInterval: 0.1)
        for note in 2...5 { try output.send(.noteOn(channel: 0, note: UInt8(note), velocity: 1)) }
        #expect(notices.lock.withLock { notices.names } == ["LC6000"])
        inner.release()
        queue.drain()
        #expect(inner.sent.count == 1)   // only the one in flight; the rest were dropped
    }

    @Test("A stuck port that sends again is no longer stuck: a reopened output starts fresh")
    func recovers() throws {
        let queue = MIDISendQueue(label: "test", stuckAfter: 0.05) { _ in }
        let stuckOne = BlockingOutput()
        let first = queue.output(stuckOne, name: "LC6000")
        try first.send(.noteOn(channel: 0, note: 1, velocity: 1))
        Thread.sleep(forTimeInterval: 0.1)
        stuckOne.release()
        queue.drain()
        let fresh = BlockingOutput()
        fresh.release()
        let second = queue.output(fresh, name: "LC6000")
        try second.send(.noteOn(channel: 0, note: 2, velocity: 1))
        queue.drain()
        #expect(fresh.sent.count == 1)
    }

    @Test("The backlog is bounded: past it the oldest LED writes are dropped, never the newest")
    func bounded() throws {
        let inner = BlockingOutput()
        let queue = MIDISendQueue(label: "test", backlog: 4)
        let output = queue.output(inner)
        try output.send(.noteOn(channel: 0, note: 0, velocity: 1))   // in flight
        Thread.sleep(forTimeInterval: 0.02)
        for note in 1...10 { try output.send(.noteOn(channel: 0, note: UInt8(note), velocity: 1)) }
        inner.release()
        queue.drain()
        #expect(inner.sent == [0, 7, 8, 9, 10].map { "\(MIDIEvent.noteOn(channel: 0, note: UInt8($0), velocity: 1))" })
    }
}
