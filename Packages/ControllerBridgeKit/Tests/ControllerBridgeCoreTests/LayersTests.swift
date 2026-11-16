import ControllerBridgeCore
import Foundation
import Testing

/// Following the controller's own deck layers (#79). The LC6000's Shift + deck select (ch16 note 55) steps its layer
/// ch1 → ch2 → ch3 → ch4; note 51 goes out at velocity 0 on the old channel and 127 on the new one, and every control
/// then arrives on the new channel. MIDI channel N drives Syndicate deck N. Literals are from the hardware capture.
@Suite("Controller layers")
struct LayersTests {
    @Test("The LC6000 profile lists its four layers, channel N → deck N, and note 51 as the active-layer signal")
    func lc6000Layers() throws {
        let midi = try Mapping.bundledDefault().midi
        #expect(midi.layers == [
            Mapping.Layer(channel: 1, deck: 1), Mapping.Layer(channel: 2, deck: 2),
            Mapping.Layer(channel: 3, deck: 3), Mapping.Layer(channel: 4, deck: 4),
        ])
        #expect(midi.layerNote == 51)
    }

    @Test("The mapping check guards layers: channel 1-16, deck 1-4, the layer note 0-127, and no channel used twice")
    func layerChecks() {
        #expect(Mapping.problems(in: Data(#"{"midi": {"layers": [{"channel": 17, "deck": 5}], "layer_note": 200}}"#.utf8)) == [
            "midi.layers[0].channel: 17 is out of range, expected 1-16",
            "midi.layers[0].deck: 5 is out of range, expected 1-4",
            "midi.layer_note: 200 is out of range, expected 0-127",
        ])
        #expect(Mapping.problems(in: Data(#"{"midi": {"layers": [{"channel": 1, "deck": 1}, {"channel": 1, "deck": 2}]}}"#.utf8)) == [
            "midi.layers[1].channel: channel 1 is also midi.layers[0].channel",
        ])
    }

    static let lc6000Layers = [
        Mapping.Layer(channel: 1, deck: 1), Mapping.Layer(channel: 2, deck: 2),
        Mapping.Layer(channel: 3, deck: 3), Mapping.Layer(channel: 4, deck: 4),
    ]
    static let unit = MIDIEndpoint(id: 1001, name: "Denon DJ LC6000 PRIME LC6000 PRIME Controller")

    @Test("A controller entry that follows layers (the default when the profile has them) runs as one entry per layer")
    func followingEntryExpands() {
        let entry = ControllerSettings(deck: 1, input: Self.unit, output: nil)
        #expect(ControllerSettings.expanded([entry], layers: Self.lc6000Layers) == [
            ControllerSettings(deck: 1, input: Self.unit, output: nil, channel: 1, followLayers: true),
            ControllerSettings(deck: 2, input: Self.unit, output: nil, channel: 2, followLayers: true),
            ControllerSettings(deck: 3, input: Self.unit, output: nil, channel: 3, followLayers: true),
            ControllerSettings(deck: 4, input: Self.unit, output: nil, channel: 4, followLayers: true),
        ])
    }

    @Test("Following turned off, or a profile with no layers: the entry runs as it is")
    func notFollowing() {
        let off = ControllerSettings(deck: 2, input: Self.unit, output: nil, followLayers: false)
        #expect(ControllerSettings.expanded([off], layers: Self.lc6000Layers) == [off])
        let plain = ControllerSettings(deck: 2, input: nil, output: nil)
        #expect(ControllerSettings.expanded([plain], layers: []) == [plain])
    }

    @Test("Settings saved before #79 still read, with following left to the default")
    func oldSettingsDecode() throws {
        let json = #"{"deck": 3, "input": null, "output": null}"#
        let entry = try JSONDecoder().decode(ControllerSettings.self, from: Data(json.utf8))
        #expect(entry == ControllerSettings(deck: 3, input: nil, output: nil))
        #expect(entry.followLayers == nil)
    }
}
