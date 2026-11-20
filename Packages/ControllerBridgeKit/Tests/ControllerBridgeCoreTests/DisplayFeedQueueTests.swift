import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed's queue (#616): the Coordinator's sends are handed to a worker, never sent on the event path, and
/// dropped, not queued, once the worker is a backlog behind. A manual worker stands in for the app's serial queue.
@Suite("Display feed: the queue")
struct DisplayFeedQueueTests {
    final class Worker: @unchecked Sendable {
        var jobs: [@Sendable () -> Void] = []
        func runAll() {
            let now = jobs
            jobs.removeAll()
            for job in now { job() }
        }
    }

    static func message(_ n: Int) -> OSCMessage { OSCMessage("/DeckBridge/Display/deck", [.int(Int32(n))]) }

    @Test("A send goes out on the worker, not on the caller")
    func offTheCaller() {
        let inner = Rig.FakeOSC(), worker = Worker()
        let queue = DisplayFeedQueue(inner, backlog: 4) { worker.jobs.append($0) }
        queue.send(Self.message(1))
        #expect(inner.sent == [])
        worker.runAll()
        #expect(inner.sent == [Self.message(1)])
    }

    @Test("Behind by the backlog, later sends are dropped and counted; once the worker catches up, sends go again")
    func dropsWhenBehind() {
        let inner = Rig.FakeOSC(), worker = Worker()
        let queue = DisplayFeedQueue(inner, backlog: 4) { worker.jobs.append($0) }
        for n in 1...6 { queue.send(Self.message(n)) }
        #expect(worker.jobs.count == 4)
        #expect(queue.dropped == 2)
        worker.runAll()
        #expect(inner.sent == (1...4).map(Self.message))
        queue.send(Self.message(7))
        worker.runAll()
        #expect(inner.sent.last == Self.message(7))
    }
}
