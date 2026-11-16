import ControllerBridgeCore
import Foundation
import Testing

/// Picking a controller profile by device name (#43), at the Coordinator seam. Which device a controller then binds
/// to (saved unique id first, then name) is #20's.
@Suite("Profile matching")
struct ProfileMatchingTests {
    /// A Coordinator over the given profiles and MIDI sources, with a destination named like each source.
    final class ProfileRig {
        let midi: Rig.FakeMIDISystem
        let osc = Rig.FakeOSC()
        let log = Rig.FakeLog()
        let coordinator: Coordinator

        init(profiles: [ControllerProfile], sources: [MIDIEndpoint]) {
            midi = Rig.FakeMIDISystem(
                sources: sources,
                destinations: sources.map { MIDIEndpoint(id: $0.id + 1000, name: $0.name) }
            )
            coordinator = Coordinator(profiles: profiles, midi: midi, osc: osc, clock: Rig.FakeClock(), log: log)
        }
    }

    static let iac = MIDIEndpoint(id: 1000, name: "IAC Bus 1")
    static let lc6000 = MIDIEndpoint(id: 1001, name: "DENON LC6000 PRIME")

    @Test("A device whose name matches a profile's hint gets that profile; a device with none is listed but not bridged")
    func matchesByDeviceName() throws {
        let rig = ProfileRig(profiles: try ControllerProfile.bundled(), sources: [Self.iac, Self.lc6000])
        rig.coordinator.start()

        #expect(rig.midi.connected == [Self.lc6000.id])
        #expect(rig.coordinator.status.devices == [
            DeviceStatus(name: "IAC Bus 1", profile: nil, note: "No controller profile matches IAC Bus 1, so it isn't bridged."),
            DeviceStatus(name: "DENON LC6000 PRIME", profile: "Denon LC6000 PRIME", note: nil),
        ])
        #expect(rig.coordinator.status.controllers.map(\.profile) == ["Denon LC6000 PRIME"])
    }
}
