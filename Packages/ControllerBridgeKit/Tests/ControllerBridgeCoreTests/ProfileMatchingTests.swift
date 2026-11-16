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

    static let other = MIDIEndpoint(id: 1002, name: "Some Other Controller")

    @Test("With no matching device nothing is bridged: the device is listed with a plain message, and logged")
    func noMatch() throws {
        let rig = ProfileRig(profiles: try ControllerProfile.bundled(), sources: [Self.other])
        rig.coordinator.start()
        rig.osc.sent.removeAll()

        #expect(rig.midi.connected == [])
        #expect(rig.coordinator.status.devices == [
            DeviceStatus(name: "Some Other Controller", profile: nil, note: "No controller profile matches Some Other Controller, so it isn't bridged."),
        ])
        #expect(rig.coordinator.status.controllers.map(\.profile) == [nil])
        #expect(rig.log.lines.contains("No controller profile matches Some Other Controller, so it isn't bridged."))

        rig.coordinator.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Self.other.id)
        #expect(rig.osc.sent == [])
        // A later device-list change lists it again but doesn't log it twice.
        rig.coordinator.devicesChanged()
        #expect(rig.log.lines.filter { $0.hasPrefix("No controller profile matches") }.count == 1)
    }
}
