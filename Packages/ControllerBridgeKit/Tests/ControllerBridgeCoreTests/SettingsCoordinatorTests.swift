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

    static let twin = MIDIEndpoint(id: 1005, name: "DENON LC6000 PRIME")
    static let twinOut = MIDIEndpoint(id: 2005, name: "DENON LC6000 PRIME")

    @Test("Choosing devices releases held controls, drops the old ports and connects the chosen ones, keeping the deck")
    func chooseDevices() throws {
        let rig = try Rig()
        rig.midi.sources.append(Self.twin)
        rig.midi.destinations.append(Self.twinOut)
        rig.coordinator.start()
        rig.coordinator.setDeck(3, controller: 0)
        Self.press(rig, 2)   // Cue held
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Playing", [.int(1)]))   // answers the Resend
        rig.osc.sent.removeAll()

        rig.coordinator.setDevices(input: Self.twin, output: Self.twinOut, controller: 0)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/3/Cue", [.int(0)]), Self.resend])
        #expect(rig.midi.connected == [Self.twin.id])
        #expect(rig.midi.outputs[Rig.lc6000Out.id]?.closed == true)
        #expect(rig.midi.outputs[Self.twinOut.id]?.sent.isEmpty == false)   // repainted
        #expect(rig.coordinator.status.controllers.map(\.deck) == [3])

        rig.osc.sent.removeAll()
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Self.twin.id)
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)   // the old unit: ignored
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/3/PlayPause", [.int(1)])])
    }

    @Test("Automatic (no device chosen) goes back to the first device a profile matches")
    func automaticDevices() throws {
        let rig = try Rig()
        rig.midi.sources.append(Self.twin)
        rig.coordinator.start()
        rig.coordinator.setDevices(input: Self.twin, output: nil, controller: 0)
        rig.coordinator.setDevices(input: nil, output: nil, controller: 0)
        #expect(rig.midi.connected == [Rig.lc6000.id])
    }
}
