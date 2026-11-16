import ControllerBridgeCore
import Testing

/// Settings reaching the Coordinator: deck and device changes, and LEDs off.
@Suite("Settings changes")
struct SettingsCoordinatorTests {
    static let resend = OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])

    static func press(_ rig: Rig, _ note: UInt8, on: Bool = true) {
        rig.coordinator.midi(on ? .noteOn(channel: 0, note: note, velocity: 127) : .noteOff(channel: 0, note: note, velocity: 0), source: Rig.lc6000.id)
    }

    @Test("Switching deck with Cue held releases Cue on the old deck, then resyncs on the new one")
    func deckChange() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        Self.press(rig, 2)   // Cue held on deck 1
        rig.osc.sent.removeAll()

        rig.coordinator.setDeck(2, controller: 0)
        Self.press(rig, 2, on: false)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)]), Self.resend])
        #expect(rig.coordinator.status.controllers.map(\.deck) == [2])
        #expect(rig.leds[1] == 1)   // deck 2's state isn't known yet: Play idle

        rig.osc.sent.removeAll()
        Self.press(rig, 1)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/2/PlayPause", [.int(1)])])
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        #expect(rig.leds[1] == 127)
    }
}
