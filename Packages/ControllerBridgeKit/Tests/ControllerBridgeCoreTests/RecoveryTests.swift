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

    static func unplug(_ rig: Rig) {
        rig.midi.sources = [Self.iac]
        rig.midi.destinations = []
        rig.coordinator.devicesChanged()
    }

    @Test("Unplugging releases every held control exactly once, closes the ports, and logs and shows it")
    func unplugReleasesOnce() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)    // Cue held
        rig.coordinator.midi(.controlChange(channel: 0, controller: 55, value: 1), source: Rig.lc6000.id)  // nudge
        rig.osc.sent.removeAll()

        Self.unplug(rig)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)]),
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]),
        ])
        #expect(rig.midi.connected == [])
        #expect(rig.midi.outputs[Rig.lc6000Out.id]?.closed == true)
        #expect(rig.coordinator.status.controllers == [ControllerStatus(deck: 1, connected: false, lastEvent: "Disconnected DENON LC6000 PRIME")])
        #expect(rig.log.lines.last == "Disconnected DENON LC6000 PRIME")

        rig.coordinator.devicesChanged()
        #expect(rig.osc.sent.count == 2)
    }
}
