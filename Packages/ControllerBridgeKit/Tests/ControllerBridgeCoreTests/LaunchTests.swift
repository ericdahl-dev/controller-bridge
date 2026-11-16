import ControllerBridgeCore
import Foundation
import Testing

/// Launch with the saved settings (#105): the Coordinator starts straight on the chosen devices, deck, layers and LEDs
/// switch, so it never touches a device, deck or LED the user didn't choose, not even for a moment.
@Suite("Launch with saved settings")
struct LaunchTests {
    static let unitB = MIDIEndpoint(id: 1005, name: "DENON LC6000 PRIME")
    static let unitBOut = MIDIEndpoint(id: 2005, name: "DENON LC6000 PRIME")
    static let resend = OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])

    @Test("Saved on unit B with unit A listed first: only B is ever connected and lit, and one Resend goes out")
    func chosenDeviceOnly() throws {
        let rig = try Rig()
        rig.midi.sources.append(Self.unitB)
        rig.midi.destinations.append(Self.unitBOut)

        rig.coordinator.start(controllers: [ControllerSettings(deck: 1, input: Self.unitB, output: Self.unitBOut)])

        #expect(rig.midi.everConnected == [Self.unitB.id])
        #expect(rig.midi.outputs[Rig.lc6000Out.id] == nil)
        #expect(rig.midi.outputs[Self.unitBOut.id]?.sent.isEmpty == false)
        #expect(rig.osc.sent == [Self.resend])
    }

    @Test("Saved on deck 3: nothing goes to deck 1; the first press drives deck 3")
    func savedDeck() throws {
        let rig = try Rig()
        rig.coordinator.start(controllers: [ControllerSettings(deck: 3, input: nil, output: nil)])
        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.controllers.map(\.deck) == [3])
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/3/PlayPause", [.int(1)]))
    }

    @Test("Saved with the LEDs off: launch writes no LED message at all")
    func savedLEDsOff() throws {
        let rig = try Rig()
        rig.coordinator.start(controllers: [ControllerSettings(deck: 1, input: nil, output: nil)], ledsEnabled: false)
        #expect(rig.coordinator.status.controllers.map(\.connected) == [true])
        #expect(rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? [] == [])
    }

    @Test("Saved following layers (#79): all four layers connect at launch, with one Resend")
    func savedLayers() throws {
        let rig = try Rig()
        let layers = try Mapping.bundledDefault().midi.layers
        rig.coordinator.start(controllers: ControllerSettings.expanded([ControllerSettings(deck: 1, input: nil, output: nil)], layers: layers))
        #expect(rig.coordinator.status.controllers.map(\.connected) == [true, true, true, true])
        #expect(rig.coordinator.status.controllers.map(\.deck) == [1, 2, 3, 4])
        #expect(rig.osc.sent == [Self.resend])
    }

    @Test("A saved unit that isn't plugged in: no fallback to another unit; it waits, and connects when plugged in")
    func savedUnitAbsent() throws {
        let rig = try Rig()   // only unit A is present
        rig.coordinator.start(controllers: [ControllerSettings(deck: 1, input: Self.unitB, output: Self.unitBOut)])
        #expect(rig.midi.everConnected == [])
        #expect(rig.coordinator.status.controllers.map(\.connected) == [false])
        // The panel's WAITING (#91): waiting for the device chosen in Settings, not "never connected".
        #expect(rig.coordinator.status.controllers.map(\.lastDisconnect) == [.deviceChanged])

        rig.midi.sources.append(Self.unitB)
        rig.midi.destinations.append(Self.unitBOut)
        rig.coordinator.devicesChanged()
        #expect(rig.midi.everConnected == [Self.unitB.id])
        #expect(rig.coordinator.status.controllers.map(\.connected) == [true])
    }

    @Test("A later plain start (as after the demo) keeps the LEDs switch the user set, rather than turning LEDs back on")
    func restartKeepsLEDsOff() throws {
        let rig = try Rig()
        rig.coordinator.start(controllers: [ControllerSettings(deck: 1, input: nil, output: nil)], ledsEnabled: false)
        rig.coordinator.stop()
        rig.coordinator.start()
        #expect(rig.midi.outputs[Rig.lc6000Out.id]?.sent.filter { if case .noteOn(_, _, let v) = $0 { v > 0 } else { false } } ?? [] == [])
    }
}
