@testable import ControllerBridgeCore
import Testing

/// The Diagnostics preview of the drawn layout (#465): each deck's drawn state, decoded from the messages the host
/// would send for it, whenever the jog display would draw. A unit that answered draws; one that didn't shows images;
/// with no unit, Custom shows the drawn look so it can be tried, Denon the images.
@Suite("Drawn display: the preview")
struct DrawnPreviewTests {
    static func drawnPreviews(_ events: [JogDisplayEvent]) -> [DrawnDisplayState] {
        events.compactMap { if case .drawnPreview(let state) = $0 { return state }; return nil }
    }

    @Test("No unit, Custom: every loaded deck gets a drawn preview with its deck and title")
    func noUnitCustom() throws {
        let (rig, take) = try JogDisplayPreviewNoControllerTests.rig()
        rig.coordinator.setDisplayFirmware(.custom)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 3))
        rig.clock.now = 0.1
        rig.coordinator.tick()
        let deck3 = Self.drawnPreviews(take()).last { $0.deck?.number == 3 }
        #expect(deck3?.texts[.title] == Array("Daybreak".utf8))
        #expect(deck3?.flags.contains(.loaded) == true)
    }
}
