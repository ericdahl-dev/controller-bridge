import ControllerBridgeCore
import Foundation
import Synchronization
import Testing

/// Where OSC goes (#84, #109): Syndicate's host by IP address or by name, resolved off the caller, with the old
/// destination kept until a new one opens. The resolver and the sockets are fakes: no network.
@Suite("OSC destination")
struct OSCDestinationTests {
    /// Sockets "opened" by the destination, by address, with what each was sent. One can be told to fail.
    final class FakeSinks: @unchecked Sendable {
        final class Sink: DatagramSink, @unchecked Sendable {
            let address: String
            var sent: [[UInt8]] = []
            var fails = false
            init(_ address: String) { self.address = address }
            func send(_ bytes: [UInt8]) throws {
                if fails { throw POSIXError(.EHOSTUNREACH) }
                sent.append(bytes)
            }
        }
        var opened: [Sink] = []
        var refuse: Set<String> = []
        func open(_ host: String, _ port: Int) throws -> any DatagramSink {
            if refuse.contains(host) { throw POSIXError(.EADDRNOTAVAIL) }
            let sink = Sink("\(host):\(port)")
            opened.append(sink)
            return sink
        }
        func sink(_ address: String) -> Sink? { opened.last { $0.address == address } }
    }

    /// Answers names from a table; counts the questions.
    final class FakeResolver: HostResolver, @unchecked Sendable {
        var answers: [String: String] = [:]
        var asked: [String] = []
        func resolve(_ host: String) async throws -> String {
            asked.append(host)
            guard let ip = answers[host] else { throw POSIXError(.ENOENT) }
            return ip
        }
    }

    static let play = OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])

    static func destination(_ sinks: FakeSinks, _ resolver: any HostResolver) -> OSCDestination {
        OSCDestination(resolver: resolver, open: { try sinks.open($0, $1) }, clock: Rig.FakeClock())
    }

    @Test("An IP address opens at once, with no lookup, and sends go there")
    func ipAddress() async throws {
        let sinks = FakeSinks(), resolver = FakeResolver()
        let destination = Self.destination(sinks, resolver)
        #expect(await destination.connect(host: "192.168.1.20", port: 9090) == nil)
        destination.send(Self.play)
        #expect(resolver.asked == [])
        #expect(sinks.sink("192.168.1.20:9090")?.sent == [Self.play.encoded()])
    }

    /// Holds each lookup until the test answers it, so the test can act while a name is resolving.
    final class GatedResolver: HostResolver, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<String, any Error>] = []
        var pending: Int { lock.withLock { waiting.count } }
        func resolve(_ host: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in lock.withLock { waiting.append(continuation) } }
        }
        func answer(_ ip: String) { lock.withLock { waiting.removeFirst() }.resume(returning: ip) }
        func fail() { lock.withLock { waiting.removeFirst() }.resume(throwing: POSIXError(.ENOENT)) }
        /// Waits (briefly, in real time) until a lookup has started.
        func waitForLookup() async {
            for _ in 0..<500 where pending == 0 { try? await Task.sleep(for: .milliseconds(2)) }
        }
    }

    final class Count: @unchecked Sendable { var value = 0 }

    @Test("A name at launch doesn't wait: sends are dropped while it resolves, then go to its address; onReady fires once")
    func nameResolvesInTheBackground() async throws {
        let sinks = FakeSinks(), resolver = GatedResolver(), ready = Count()
        let destination = Self.destination(sinks, resolver)
        destination.onReady = { ready.value += 1 }
        let connecting = Task { await destination.connect(host: "studio-mac.local", port: 9090) }
        await resolver.waitForLookup()

        destination.send(Self.play)                      // while resolving: dropped, nothing opened
        #expect(sinks.opened.isEmpty)

        resolver.answer("192.168.1.30")
        #expect(await connecting.value == nil)
        destination.send(Self.play)
        #expect(sinks.sink("192.168.1.30:9090")?.sent == [Self.play.encoded()])
        #expect(ready.value == 1)
    }

    @Test("A name that can't be found says so, and the old destination keeps sending")
    func unknownNameKeepsTheOldOne() async throws {
        let sinks = FakeSinks(), resolver = FakeResolver()
        let destination = Self.destination(sinks, resolver)
        #expect(await destination.connect(host: "192.168.1.20", port: 9090) == nil)
        #expect(await destination.connect(host: "studio-mac.local", port: 9090) == "Can't find studio-mac.local on the network")
        destination.send(Self.play)
        #expect(sinks.sink("192.168.1.20:9090")?.sent == [Self.play.encoded()])
    }

    @Test("A lookup that hangs gives up after the timeout with the same message, so Settings is never stuck checking")
    func hungLookupTimesOut() async throws {
        let sinks = FakeSinks(), resolver = GatedResolver()   // never answered
        let destination = OSCDestination(resolver: resolver, open: { try sinks.open($0, $1) }, clock: Rig.FakeClock(),
                                         lookupTimeout: .milliseconds(50))
        #expect(await destination.connect(host: "studio-mac.local", port: 9090) == "Can't find studio-mac.local on the network")
        #expect(sinks.opened.isEmpty)
        resolver.fail()   // let the hung lookup go
    }
}
