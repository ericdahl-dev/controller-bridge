import ControllerBridgeCore
import Testing

/// While the capture window (#186) records a controller, the bridge stops driving Syndicate from it, so pressing Play
/// to capture it doesn't start a track.
@Suite("Capture pause")
struct CapturePauseTests {
    static let iac = MIDIEndpoint(id: 1000, name: "IAC Bus 1")

    static func cc(_ rig: Rig, _ controller: UInt8, _ value: UInt8) {
        rig.coordinator.midi(.controlChange(channel: 0, controller: controller, value: value), source: Rig.lc6000.id)
    }

    static func platterAt(_ rig: Rig, _ position: Int) {
        cc(rig, 17, UInt8(position >> 7))
        cc(rig, 49, UInt8(position & 0x7F))
    }

    static func started() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("Capturing a source releases what it held, once, and then its MIDI reaches no Syndicate")
    func pauses() throws {
        let rig = try Self.started()
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)  // Cue held
        rig.osc.sent.removeAll()

        rig.coordinator.setCapture(source: Rig.lc6000.id)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)])])
        rig.osc.sent.removeAll()

        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)  // Play
        rig.coordinator.midi(.noteOff(channel: 0, note: 1, velocity: 0), source: Rig.lc6000.id)
        Self.platterAt(rig, 4000)
        Self.platterAt(rig, 4100)
        #expect(rig.osc.sent == [])
        #expect(rig.coordinator.status.controllers.map(\.connected) == [true])
    }

    @Test("Ending the capture gives the controller back, and the jog's first position only seeds it: no jump")
    func resumes() throws {
        let rig = try Self.started()
        Self.platterAt(rig, 79)
        rig.coordinator.setCapture(source: Rig.lc6000.id)
        Self.platterAt(rig, 9000)  // turned while capturing
        rig.coordinator.setCapture(source: nil)
        rig.osc.sent.removeAll()

        Self.platterAt(rig, 9010)
        #expect(rig.osc.sent == [])
        Self.platterAt(rig, 9020)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)])])
        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)]))
    }

    @Test("Unplugging the captured controller ends the capture: replugged, it drives Syndicate again")
    func unplugEnds() throws {
        let rig = try Self.started()
        rig.coordinator.setCapture(source: Rig.lc6000.id)
        rig.midi.sources = [Self.iac]
        rig.midi.destinations = []
        rig.coordinator.devicesChanged()
        rig.midi.sources = [Self.iac, Rig.lc6000]
        rig.midi.destinations = [Rig.lc6000Out]
        rig.coordinator.devicesChanged()
        rig.osc.sent.removeAll()

        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
    }

    @Test("The pitch fader swept during the capture waits for pickup after it, instead of jumping the tempo")
    func pitchWaitsForPickup() throws {
        let rig = try Self.started()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(0.5)]))
        PickupTests.fader(rig, 0x60)  // picked up at Syndicate's 0.5
        rig.coordinator.setCapture(source: Rig.lc6000.id)
        PickupTests.fader(rig, 0x00)  // swept while capturing
        PickupTests.fader(rig, 0x7F)
        rig.coordinator.setCapture(source: nil)
        rig.osc.sent.removeAll()

        PickupTests.fader(rig, 0x7E)
        #expect(rig.osc.sent == [])
    }

    @Test("A layer switched during the capture is the active one after it: Play on ch1 then goes to deck 2")
    func layerFollowedDuringCapture() throws {
        let rig = try LayersTests.layered()
        rig.coordinator.setCapture(source: Rig.lc6000.id)
        LayersTests.note(rig, channel: 1, 51, 0)
        LayersTests.note(rig, channel: 2, 51, 127)
        rig.coordinator.setCapture(source: nil)
        rig.osc.sent.removeAll()

        LayersTests.note(rig, channel: 1, 1, 127)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/2/PlayPause", [.int(1)])])
    }
}
