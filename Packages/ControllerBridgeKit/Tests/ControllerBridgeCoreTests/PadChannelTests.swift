import Foundation
@testable import ControllerBridgeCore
import Testing

/// Pads on their own MIDI channel (#224), as on the Pioneer DDJ-400/FLX4 (pads on 8 and 10) and Denon MC7000 (5-8).
@Suite("Pad channel mapping")
struct PadChannelMappingTests {
    @Test("Left out, pads share the deck's channel: the bundled LC6000 has no pad channel anywhere")
    func lc6000() throws {
        let mapping = try Mapping.bundledDefault()
        #expect(mapping.pads.channel == nil)
        #expect(mapping.midi.layers.map(\.padChannel) == [nil, nil, nil, nil])
    }

    @Test("A profile sets the pad channel for its deck, and for each deck layer")
    func decodes() throws {
        let pads = try JSONDecoder().decode(Mapping.Pads.self, from: Data(#"{ "channel": 8 }"#.utf8))
        #expect(pads.channel == 8)
        let layer = try JSONDecoder().decode(Mapping.Layer.self, from: Data(#"{ "channel": 2, "deck": 2, "pad_channel": 10 }"#.utf8))
        #expect(layer == Mapping.Layer(channel: 2, deck: 2, padChannel: 10))
        let plain = try JSONDecoder().decode(Mapping.Layer.self, from: Data(#"{ "channel": 3, "deck": 3 }"#.utf8))
        #expect(plain.padChannel == nil)
    }
}
