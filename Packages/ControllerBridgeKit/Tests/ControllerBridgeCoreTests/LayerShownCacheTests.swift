@testable import ControllerBridgeCore
import Testing

/// One "shown" cache per output (#554): what the unit's lights are now, whichever layer set them. A deck select step
/// (#420) sends only the lights that differ for the new layer.
@Suite("Layer shown cache")
struct LayerShownCacheTests {
    typealias Press = PressLitButtonsTests

    static func noteOns(_ rig: Rig) -> [String] {
        (rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? []).compactMap {
            if case .noteOn(let channel, let note, let velocity) = $0 { "ch\(channel + 1) \(note)=\(velocity)" } else { nil }
        }
    }

    @Test("Deck select to a layer that differs only in Play (deck 2 playing): exactly that one light goes out")
    func onlyTheDifference() throws {
        let rig = try LayersTests.layered()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        rig.midi.outputs[Rig.lc6000Out.id]?.sent.removeAll()
        Press.note(rig, 23, down: true)
        Press.note(rig, 23, down: false)
        #expect(Self.noteOns(rig) == ["ch1 1=127"])
    }

    @Test("And back: only Play again, dim")
    func back() throws {
        let rig = try LayersTests.layered()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        Press.note(rig, 23, down: true)
        Press.note(rig, 23, down: false)
        for _ in 0..<3 {   // round to layer 1 (layers 3 and 4 show deck 3 and 4, not playing: Play dim on the first)
            rig.clock.now += 1
            Press.note(rig, 23, down: true)
            Press.note(rig, 23, down: false)
            if rig.coordinator.status.controllers[2].activeLayer {
                rig.midi.outputs[Rig.lc6000Out.id]?.sent.removeAll()
            }
        }
        #expect(rig.coordinator.status.controllers[0].activeLayer)
        #expect(Self.noteOns(rig).isEmpty)   // layers 3, 4 and 1 all show the same lights
    }
}
