import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed at the Coordinator seam (#490, #616): Syndicate's feedback and the controller's MIDI in, the feed's
/// OSC out to its own fake port. Syndicate's factory deck colors (#123): deck 1 red, deck 2 yellow.
@Suite("Display feed at the Coordinator")
struct DisplayFeedCoordinatorTests {
    static let on = DisplayFeedSettings(enabled: true, host: "192.168.1.40", port: 9100)

    /// A rig with the feed's port attached, the feed still off.
    static func rig() throws -> (Rig, Rig.FakeOSC) {
        let rig = try Rig()
        let feed = Rig.FakeOSC()
        rig.coordinator.attachDisplayFeed(feed)
        return (rig, feed)
    }

    /// The full snapshot of a deck, in the feed's order.
    static func snapshot(deck: Int, color: Int32, title: String, artist: String) -> [OSCMessage] {
        [
            OSCMessage("/DeckBridge/Display/deck", [.int(Int32(deck))]),
            OSCMessage("/DeckBridge/Display/color", [.int(color)]),
            OSCMessage("/DeckBridge/Display/title", [.string(title)]),
            OSCMessage("/DeckBridge/Display/artist", [.string(artist)]),
        ]
    }

    @Test("Turned on with a controller connected: one snapshot of its deck's number, color, title and artist")
    func onSendsSnapshot() throws {
        let (rig, feed) = try Self.rig()
        rig.coordinator.start()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo())
        #expect(feed.sent == [])
        rig.coordinator.setDisplayFeed(Self.on)
        #expect(feed.sent == Self.snapshot(deck: 1, color: 0xFF0000, title: "Daybreak", artist: "Bill Hamel, Jeremus"))
    }
}
