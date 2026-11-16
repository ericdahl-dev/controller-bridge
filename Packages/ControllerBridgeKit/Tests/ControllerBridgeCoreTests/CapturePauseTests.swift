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
}
