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

/// The Coordinator seam (#224): a test-only profile whose pads (notes 32-39) are on channel 8, its other controls on 1.
/// Velocities by hand from the 0b00RRGGBB table: Syndicate's default slot 1 red (255, 0, 0) → 48.
@Suite("Pad channel at the Coordinator")
struct PadChannelCoordinatorTests {
    static let ch8 = #"{ "pads": { "channel": 8 } }"#

    static func started(_ override: String?) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    /// Presses and releases `note` on MIDI channel `channel` (1-16).
    static func press(_ rig: Rig, _ note: UInt8, channel: UInt8) {
        rig.coordinator.midi(.noteOn(channel: channel - 1, note: note, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOff(channel: channel - 1, note: note, velocity: 0), source: Rig.lc6000.id)
    }

    /// The last velocity written to `note` on `channel` (1-16).
    static func led(_ rig: Rig, _ note: UInt8, channel: UInt8) -> UInt8? {
        var out: UInt8?
        for case let .noteOn(ch, n, velocity) in rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? [] where ch == channel - 1 && n == note {
            out = velocity
        }
        return out
    }

    static let cues = OSCMessage("/Syndicate/Deck/1/Cues", (1...8).flatMap { [OSCArgument.int(Int32($0)), .string("c\($0)")] })

    @Test("Pad 1 on channel 8 holds hot cue 1; the same note on channel 1 isn't a pad")
    func padsOnTheirChannel() throws {
        let rig = try Self.started(Self.ch8)
        Self.press(rig, 32, channel: 8)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(1)]),
                                 OSCMessage("/Syndicate/Deck/1/HotCue", [.int(1), .int(0)])])
        rig.osc.sent.removeAll()
        Self.press(rig, 32, channel: 1)
        #expect(rig.osc.sent == [])
    }

    @Test("Pad LEDs go out on channel 8 and button LEDs stay on 1: pad 1 red (48) on 8, Hot Cue's button (27) full on 1")
    func ledsOnTheirChannels() throws {
        let rig = try Self.started(Self.ch8)
        rig.coordinator.feedback(Self.cues)
        #expect(Self.led(rig, 32, channel: 8) == 48)
        #expect(Self.led(rig, 32, channel: 1) == nil)
        #expect(Self.led(rig, 27, channel: 1) == 127)
    }

    @Test("The LED sweep's color pass lights the pads on their channel (8) and the ring on the deck's (1)")
    func sweepOnPadChannel() throws {
        let rig = try Self.started(Self.ch8)
        rig.midi.outputs[Rig.lc6000Out.id]?.sent.removeAll()
        rig.coordinator.startLEDSweep()
        let sent = rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? []
        let pads = sent.filter { if case .noteOn(_, let n, _) = $0 { return (32...39).contains(n) }; return false }
        #expect(pads.count == 8)
        #expect(pads.allSatisfy { if case .noteOn(7, _, 0) = $0 { return true }; return false })
        let ring = try Mapping.bundledDefault().leds.ring
        #expect(sent.contains(.noteOn(channel: 0, note: UInt8(ring), velocity: 0)))
    }
}
