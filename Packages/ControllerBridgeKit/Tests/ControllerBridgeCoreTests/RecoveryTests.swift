import ControllerBridgeCore
import Testing

/// Unplug, replug, sleep and quit: nothing is left stuck in Syndicate, and the controller comes back by itself.
@Suite("Recovery")
struct RecoveryTests {
    static let resend = OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])
    static let iac = MIDIEndpoint(id: 1000, name: "IAC Bus 1")

    @Test("Starting with no controller is fine; it connects and resyncs when it appears")
    func startsWithoutController() throws {
        let rig = try Rig()
        rig.midi.sources = [Self.iac]
        rig.midi.destinations = []
        rig.coordinator.start()
        #expect(rig.midi.connected == [])
        #expect(rig.coordinator.status.controllers.map(\.connected) == [false])
        #expect(rig.log.lines.last == "No controller matching \"LC6000\" yet")

        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.osc.sent.removeAll()
        rig.midi.sources = [Self.iac, Rig.lc6000]
        rig.midi.destinations = [Rig.lc6000Out]
        rig.coordinator.devicesChanged()

        #expect(rig.midi.connected == [Rig.lc6000.id])
        #expect(rig.leds[1] == 127)   // painted from the state that arrived while unplugged
        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.controllers.map(\.connected) == [true])
        #expect(rig.log.lines.last == "Connected DENON LC6000 PRIME")
    }
}
