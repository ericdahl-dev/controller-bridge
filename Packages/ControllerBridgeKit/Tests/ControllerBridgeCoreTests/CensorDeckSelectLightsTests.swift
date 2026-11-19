@testable import ControllerBridgeCore
import Testing

/// Censor shows reverse, and the deck select button flashes (#477).
@Suite("Censor and deck select lights")
struct CensorDeckSelectLightsTests {
    typealias Press = PressLitButtonsTests

    @Test("Censor (7) is full while held, and idle (1) again on release")
    func censorHeld() throws {
        let rig = try Press.started()
        #expect(rig.leds[7] == 1)
        Press.note(rig, 7, down: true)
        #expect(rig.leds[7] == 127)
        Press.note(rig, 7, down: false)
        #expect(rig.leds[7] == 1)
    }

    @Test("Shift + Censor latches reverse: Censor stays full after release, until the next Shift + Censor")
    func censorLatched() throws {
        let rig = try Press.started()
        Press.note(rig, 26, down: true)
        Press.note(rig, 7, down: true)
        Press.note(rig, 7, down: false)
        Press.note(rig, 26, down: false)
        #expect(rig.leds[7] == 127)
        Press.note(rig, 26, down: true)
        Press.note(rig, 7, down: true)
        Press.note(rig, 7, down: false)
        Press.note(rig, 26, down: false)
        #expect(rig.leds[7] == 1)
    }

    @Test("Release-all (here the Mac going to sleep) turns a latched reverse off, and Censor's light with it")
    func censorReleaseAll() throws {
        let rig = try Press.started()
        Press.note(rig, 26, down: true)
        Press.note(rig, 7, down: true)
        Press.note(rig, 7, down: false)
        Press.note(rig, 26, down: false)
        rig.coordinator.willSleep()
        #expect(rig.leds[7] == 1)
    }

    @Test("Release-all with Censor still held turns its light back to idle too")
    func censorHeldReleaseAll() throws {
        let rig = try Press.started()
        Press.note(rig, 7, down: true)
        rig.coordinator.willSleep()
        #expect(rig.leds[7] == 1)
    }

    @Test("Deck select (23), with no layers: idle dim, full while pressed")
    func deckSelectAlone() throws {
        let rig = try Press.started()
        #expect(rig.leds[23] == 1)
        Press.note(rig, 23, down: true)
        #expect(rig.leds[23] == 127)
        Press.note(rig, 23, down: false)
        #expect(rig.leds[23] == 1)
    }

    /// The LC6000 with its deck layers: deck select steps to the next layer (#420).
    static func layered() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers))
        return rig
    }

    @Test("Deck select with layers: the press steps the layer and lights the button full on the new one; release, idle")
    func deckSelectLayers() throws {
        let rig = try Self.layered()
        #expect(rig.leds[23] == 1)
        Press.note(rig, 23, down: true)
        #expect(rig.leds[23] == 127)
        Press.note(rig, 23, down: false)
        #expect(rig.leds[23] == 1)
    }

    @Test("Stepping round every layer and back, deck select is idle after each release: no layer keeps it held")
    func deckSelectRoundTrip() throws {
        let rig = try Self.layered()
        for _ in 0..<(LayersTests.lc6000Layers.count + 1) {
            Press.note(rig, 23, down: true)
            Press.note(rig, 23, down: false)
            #expect(rig.leds[23] == 1)
        }
    }
}
