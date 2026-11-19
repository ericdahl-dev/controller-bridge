@testable import ControllerBridgeCore
import Testing

/// Rapid deck layer steps (#428): on the unit, four quick deck select presses (about 160 note-ons, four color messages
/// and four display switches in two seconds) hung it. The layer switches at once for the controls. A lone step repaints
/// at once; steps that follow within the settle interval wait, and the last layer is repainted once when they settle.
@Suite("Layer settle")
struct LayerSettleTests {
    typealias Press = PressLitButtonsTests

    static func ledWrites(_ rig: Rig) -> Int {
        (rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? []).filter { if case .noteOn = $0 { true } else { false } }.count
    }

    /// Note-on writes to the LC6000's LED output since `from`.
    static func writes(_ rig: Rig, from: Int) -> Int { ledWrites(rig) - from }

    @Test("A lone step repaints at once, as before")
    func lone() throws {
        let rig = try CensorDeckSelectLightsTests.layered()
        rig.clock.now = 10
        let before = Self.ledWrites(rig)
        Press.note(rig, 23, down: true)
        #expect(Self.writes(rig, from: before) > 30)
    }

    @Test("Four steps 0.25 s apart: the first repaints at once, the rest wait and the last layer is repainted once")
    func coalesced() throws {
        let rig = try CensorDeckSelectLightsTests.layered()
        rig.clock.now = 10
        rig.coordinator.tick()
        let start = Self.ledWrites(rig)
        var afterFirst = 0
        for step in 0..<4 {
            rig.clock.now = 10 + Double(step) * 0.25
            Press.note(rig, 23, down: true)
            Press.note(rig, 23, down: false)
            rig.coordinator.tick()
            if step == 0 { afterFirst = Self.writes(rig, from: start) }
        }
        #expect(afterFirst > 30)
        #expect(Self.writes(rig, from: start) == afterFirst)   // steps 2-4 sent nothing yet
        rig.clock.now = 10.75 + LayerSettle.interval
        rig.coordinator.tick()
        let settled = Self.writes(rig, from: start)
        #expect(settled > afterFirst + 30)                     // the last layer, once
        rig.clock.now = 12
        rig.coordinator.tick()
        #expect(Self.writes(rig, from: start) == settled)
        // Four steps from layer 1: back on layer 1, and it's the one in front.
        #expect(rig.coordinator.status.controllers.map(\.activeLayer) == [true, false, false, false])
    }

    @Test("The controls switch at once: a press right after a step goes to the new layer's deck")
    func controlsAtOnce() throws {
        let rig = try CensorDeckSelectLightsTests.layered()
        rig.osc.sent.removeAll()
        Press.note(rig, 23, down: true)
        Press.note(rig, 23, down: false)
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)   // Play
        #expect(rig.osc.sent.contains(OSCMessage("/Syndicate/Deck/2/PlayPause", [.int(1)])))
    }
}
