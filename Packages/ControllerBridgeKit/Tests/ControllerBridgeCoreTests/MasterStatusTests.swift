import ControllerBridgeCore
import Testing

/// The status says MASTER by the same rule as the Master LED: the deck is synced and its tempo slider is enabled (#53).
@Suite("Master status")
struct MasterStatusTests {
    static func deck(_ rig: Rig, _ path: String, _ value: Int32) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [.int(value)]))
    }

    @Test("Master follows Sync while the tempo slider is enabled, and drops when the slider is disabled")
    func masterFollowsSyncAndSlider() throws {
        let rig = try Rig()
        rig.coordinator.start()
        #expect(rig.coordinator.status.controllers[0].master == false)

        Self.deck(rig, "Sync", 1)
        #expect(rig.coordinator.status.controllers[0].master == true)

        Self.deck(rig, "TempoSliderEnabled", 0)
        #expect(rig.coordinator.status.controllers[0].master == false)

        Self.deck(rig, "TempoSliderEnabled", 1)
        #expect(rig.coordinator.status.controllers[0].master == true)

        Self.deck(rig, "Sync", 0)
        #expect(rig.coordinator.status.controllers[0].master == false)
    }
}
