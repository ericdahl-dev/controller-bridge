import Foundation
import Synchronization

/// The display feed's sender (#490, #616): every send is handed to a worker, so the Coordinator's event path never
/// waits on the network. Once the worker is `backlog` sends behind, later sends are dropped and counted, never queued:
/// the feed must not slow DeckBridge however fast Syndicate's feedback comes (#490 story 25).
public final class DisplayFeedQueue: OSCSender {
    /// Runs a job on the worker.
    public typealias Run = @Sendable (@escaping @Sendable () -> Void) -> Void

    private let inner: any OSCSender
    private let backlog: Int
    private let run: Run
    private struct State {
        var pending = 0
        var dropped = 0
    }
    private let state = Mutex(State())

    /// `inner` is the display's UDP destination; `run` puts a job on the worker.
    public init(_ inner: any OSCSender, backlog: Int = 32, run: @escaping Run) {
        self.inner = inner
        self.backlog = backlog
        self.run = run
    }

    /// On its own serial queue.
    public convenience init(_ inner: any OSCSender, backlog: Int = 32) {
        let queue = DispatchQueue(label: "DeckBridge display feed")
        self.init(inner, backlog: backlog) { queue.async(execute: $0) }
    }

    /// Sends dropped because the worker was behind.
    public var dropped: Int { state.withLock { $0.dropped } }

    public func send(_ message: OSCMessage) {
        let taken = state.withLock { state -> Bool in
            guard state.pending < backlog else {
                state.dropped += 1
                return false
            }
            state.pending += 1
            return true
        }
        guard taken else { return }
        run { [self] in
            inner.send(message)
            state.withLock { $0.pending -= 1 }
        }
    }
}
