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
}
