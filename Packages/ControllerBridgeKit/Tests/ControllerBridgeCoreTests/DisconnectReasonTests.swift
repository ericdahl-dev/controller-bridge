import ControllerBridgeCore
import Testing

/// Why a controller disconnected, and whose it was (#91): the panel says "unplugged" only for an unplug, and keeps the
/// controller's name after it's gone.
@Suite("Disconnect reasons")
struct DisconnectReasonTests {
    static func started() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        return rig
    }

    @Test("An unplug keeps the controller's profile name as lastProfile, and says it was unplugged")
    func unplug() throws {
        let rig = try Self.started()
        rig.midi.sources = []
        rig.coordinator.devicesChanged()
        let status = try #require(rig.coordinator.status.controllers.first)
        #expect(status.profile == nil)
        #expect(status.lastProfile == "Custom mapping")
        #expect(status.lastDisconnect == .unplugged)
    }

    @Test("A failed LED send is a send failure, not an unplug")
    func sendFailed() throws {
        let rig = try Self.started()
        rig.midi.outputs[Rig.lc6000Out.id]?.failing = true
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        #expect(rig.coordinator.status.controllers.first?.lastDisconnect == .sendFailed)
    }

    @Test("A read error on the controller's input is an input failure")
    func inputFailed() throws {
        let rig = try Self.started()
        rig.coordinator.inputFailed(source: Rig.lc6000.id)
        #expect(rig.coordinator.status.controllers.first?.lastDisconnect == .inputFailed)
    }

    @Test("Choosing other devices in Settings is a device change")
    func deviceChanged() throws {
        let rig = try Self.started()
        rig.coordinator.setDevices(input: MIDIEndpoint(id: 9999, name: "Not here"), output: nil, controller: 0)
        #expect(rig.coordinator.status.controllers.first?.lastDisconnect == .deviceChanged)
        #expect(rig.coordinator.status.controllers.first?.lastProfile == "Custom mapping")
    }

    @Test("Connected from the start: nothing has disconnected yet")
    func neverDisconnected() throws {
        let rig = try Self.started()
        #expect(rig.coordinator.status.controllers.first?.lastDisconnect == nil)
        #expect(rig.coordinator.status.controllers.first?.lastProfile == "Custom mapping")
    }
}
