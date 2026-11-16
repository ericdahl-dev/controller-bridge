import ControllerBridgePresentation
import Testing

/// A controller following its own deck layers (#79): the hardware picks the deck, so the panel says so.
@Suite("Layers presentation")
struct LayersPresentationTests {
    @Test("Following layers: the block shows the active layer's deck with the note \"Following controller layers\"")
    func followingBlock() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096),
                                                    deck: 2, followsLayers: true))
        let block = status.blocks.first
        #expect(block?.deck == 2)
        #expect(block?.followsLayers == true)
        #expect(block?.deckNote == "Following controller layers")
    }

    @Test("A controller with a fixed deck has no note")
    func fixedBlock() {
        let status = StatusPresentation(BridgeState(controller: .connected(profile: "Denon LC6000 PRIME"), feedback: .live(port: 9096), deck: 2))
        #expect(status.blocks.first?.followsLayers == false)
        #expect(status.blocks.first?.deckNote == nil)
    }
}
