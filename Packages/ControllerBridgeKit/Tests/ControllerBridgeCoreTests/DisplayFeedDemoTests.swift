import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed during the demo (#625, #490 story 24): the Engine swaps in the demo's own Coordinator, and the
/// feed goes with it. The feed's fake port is attached to the real Coordinator, as the app attaches it.
@Suite("Display feed: the demo")
struct DisplayFeedDemoTests {
    /// Keeps the session the Engine makes, so a test can drive it after the pipe ends.
    final class Made: @unchecked Sendable {
        var session: DemoSession?
    }

    static func demoMaker(_ rig: Rig, _ made: Made) -> @Sendable (ControllerProfile) -> DemoSession {
        let clock = rig.clock, log = rig.log
        return { profile in
            let session = DemoSession(profile: profile, clock: clock, log: log, ledOutput: Rig.FakeOutput())
            made.session = session
            return session
        }
    }

    /// The real deck in front, known: Syndicate's palette, deck 1 loaded with Daybreak, and the feed on.
    static func realRig() throws -> (Rig, Rig.FakeOSC) {
        let (rig, feed) = try DisplayFeedCoordinatorTests.rig()
        rig.coordinator.start()
        DisplayFeedCoordinatorTests.load(rig)
        rig.coordinator.feedback(DisplayFeedCoordinatorTests.factoryPalette)
        return (rig, feed)
    }

    static func run(_ rig: Rig, _ made: Made, _ events: (EventPipe.Producer) -> Void) async {
        let pipe = EventPipe()
        events(pipe.producer)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log, makeDemo: demoMaker(rig, made)).run(pipe.events)
    }

    static func text(_ feed: Rig.FakeOSC, _ name: String) -> [String] {
        feed.sent.filter { $0.address == "/DeckBridge/Display/" + name }.compactMap {
            if case .string(let value)? = $0.arguments.first { return value }
            return nil
        }
    }

    @Test("Demo on with the feed on: the demo deck's full snapshot goes out (after the hold, its Syndicate sends no palette)")
    func demoOn() async throws {
        let (rig, feed) = try Self.realRig()
        let made = Made()
        await Self.run(rig, made) {
            $0.send(.setDisplayFeed(DisplayFeedCoordinatorTests.on))
            $0.send(.displayFeedReady)
            $0.demo(on: true)
        }
        feed.sent.removeAll()
        let session = try #require(made.session)
        for step in 1...110 {
            rig.clock.now = Double(step) * 0.01
            session.tick()
        }
        #expect(Self.text(feed, "title").first == "Demo Track")
        #expect(Self.text(feed, "artist").first == "DeckBridge")
        #expect(Self.text(feed, "key").first == "Am")
        #expect(feed.sent.filter { $0.address.hasSuffix("/deck") }.count == 1)
    }

    @Test("As the demo plays, the feed follows it, changes only: the master beat moves, the track isn't sent again")
    func demoPlays() async throws {
        let (rig, feed) = try Self.realRig()
        let made = Made()
        await Self.run(rig, made) {
            $0.send(.setDisplayFeed(DisplayFeedCoordinatorTests.on))
            $0.send(.displayFeedReady)
            $0.demo(on: true)
        }
        let session = try #require(made.session)
        for step in 1...110 { rig.clock.now = Double(step) * 0.01; session.tick() }
        feed.sent.removeAll()
        // Under the 2 s keepalive, so only changes.
        for step in 111...190 { rig.clock.now = Double(step) * 0.01; session.tick() }
        let beats = feed.sent.filter { $0.address.hasSuffix("/beat") }
        // The demo plays from 0.5 s, a beat every 0.5 s: the one at 1.5 s falls here.
        #expect(beats.count == 1)
        #expect(Self.text(feed, "title").isEmpty)
    }
}
