import ControllerBridgeCore
import Foundation
import Testing

/// An accepted import (#24) swaps the running profile: held controls are released first, the controller resyncs once,
/// and the new notes take effect. The deck (a setting) and the open ports stay.
@Suite("Set profiles")
struct SetProfilesTests {
    @Test("A new profile releases held Cue, resyncs once, then Play is on its new note; the deck setting is kept")
    func swapProfile() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)])) // Syndicate answered the start Resend.
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id) // hold Cue
        rig.osc.sent.removeAll()

        var mapping = try Mapping.bundledDefault()
        mapping.notes.buttons["play"] = 60
        mapping.deck.number = 4 // ignored: the deck is a setting, not part of the profile
        rig.coordinator.setProfiles([ControllerProfile(id: "custom", name: "Custom mapping", deviceHints: ["LC6000"], mapping: mapping)])

        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)]),
            OSCMessage("/Syndicate/Feedback/Resend", [.int(1)]),
        ])
        rig.osc.sent.removeAll()

        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent.isEmpty)
        rig.coordinator.midi(.noteOn(channel: 0, note: 60, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
        // Same port: the LEDs still go to the controller's output.
        #expect(rig.midi.connected == [Rig.lc6000.id])
    }

    @Test("Two controllers on the same profile both switch, each on its own deck, with one Resend for both")
    func twoControllers() throws {
        let rig = try Rig()
        let unitB = MIDIEndpoint(id: 1005, name: "DENON LC6000 PRIME")
        rig.midi.sources.append(unitB)
        rig.coordinator.start()
        rig.coordinator.setControllers([
            ControllerSettings(deck: 1, input: nil, output: nil),
            ControllerSettings(deck: 2, input: nil, output: nil),
        ])
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)])) // answers the pending Resend
        rig.osc.sent.removeAll()

        var mapping = try Mapping.bundledDefault()
        mapping.notes.buttons["play"] = 60
        rig.coordinator.setProfiles([ControllerProfile(id: "custom", name: "Custom mapping", deviceHints: ["LC6000"], mapping: mapping)])
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])])
        rig.osc.sent.removeAll()

        rig.coordinator.midi(.noteOn(channel: 0, note: 60, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOn(channel: 0, note: 60, velocity: 127), source: unitB.id)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)]),
            OSCMessage("/Syndicate/Deck/2/PlayPause", [.int(1)]),
        ])
    }
}
