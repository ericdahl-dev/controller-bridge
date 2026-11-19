import ControllerBridgeCore
import Foundation
import Testing

/// The platter ring in its deck's exact color (#530): with the color message on, the ring takes Denon's color message
/// (exact RGB, 7 bits a channel) in place of the 64-color note-on.
@Suite("Ring in exact color")
struct RingColorMessageTests {
    /// A started LC6000 on `deck`, with the color message on.
    static func exact(deck: Int = 1) throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.setColorMessages(true)
        rig.coordinator.setDeck(deck, controller: 0)
        return rig
    }

    static func output(_ rig: Rig) throws -> Rig.FakeOutput { try #require(rig.midi.outputs[Rig.lc6000Out.id]) }

    /// The color messages sent to `note`, each as [r, g, b].
    static func colors(_ rig: Rig, note: UInt8 = 40) throws -> [[UInt8]] {
        try output(rig).colors.filter { $0.note == note }.map { [$0.red, $0.green, $0.blue] }
    }

    static func palette(_ rig: Rig, slot: Int32, _ red: Int32, _ green: Int32, _ blue: Int32) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(slot), .int(red), .int(green), .int(blue)]))
    }

    @Test("Loading a track lights the ring with one color message in the deck's exact color, top 7 bits, and no note-on")
    func trackLoad() throws {
        let rig = try Self.exact(deck: 2)
        Self.palette(rig, slot: 3, 255, 140, 0)
        let output = try Self.output(rig)
        output.sent.removeAll()
        output.colors.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(1)]))
        #expect(try Self.colors(rig) == [[127, 70, 0]])
        #expect(!output.sent.contains { if case .noteOn(_, 40, _) = $0 { true } else { false } })
    }

    @Test("Only changes go out: ticks send the ring nothing more; a deck color change sends the new color once")
    func onlyChanges() throws {
        let rig = try Self.exact(deck: 2)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(1)]))
        let before = try Self.colors(rig).count
        for step in 1...5 {
            rig.clock.now += 0.05 * Double(step)
            rig.coordinator.tick()
        }
        #expect(try Self.colors(rig).count == before)
        Self.palette(rig, slot: 3, 0, 255, 0)
        Self.palette(rig, slot: 3, 0, 255, 0)
        #expect(try Self.colors(rig).dropFirst(before) == [[0, 127, 0]])
    }

    @Test("Layers: only the layer in front sends color messages; the hidden deck's color change waits until it's shown")
    func layers() throws {
        // The color message carries no channel and Denon's firmware doesn't filter it by deck (#481), so a hidden
        // layer's message would paint the LEDs in front.
        let rig = try LayersTests.layered()
        rig.coordinator.setColorMessages(true)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(1)]))
        let output = try Self.output(rig)
        output.colors.removeAll()
        Self.palette(rig, slot: 3, 255, 0, 0)   // deck 2, hidden behind layer 1
        #expect(output.colors.isEmpty)
        LayersTests.note(rig, channel: 2, 51, 127)   // layer 2 to the front
        #expect(try Self.colors(rig).last == [127, 0, 0])
    }

    @Test("With no track the ring is off, as a color message of 0, 0, 0")
    func noTrack() throws {
        let rig = try Self.exact(deck: 2)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Loaded", [.int(0)]))
        #expect(try Self.colors(rig).last == [0, 0, 0])
    }
}
