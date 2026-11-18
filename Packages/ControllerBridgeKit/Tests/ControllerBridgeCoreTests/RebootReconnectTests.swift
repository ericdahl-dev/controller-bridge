import Foundation
@testable import ControllerBridgeCore
import Testing

/// A quick power cycle of the unit (#429): its endpoints are removed and back, with the same ids, before the device
/// change is handled. The unit comes back in standalone state (LEDs cleared, the display not in host mode), so a
/// controller removed and back is reconnected as if unplugged and plugged in again.
@Suite("Reboot reconnect")
struct RebootReconnectTests {
    /// Every note the LC6000's LED output was sent, across reopened outputs.
    static func ledNotes(_ rig: Rig) -> Set<UInt8> {
        Set((rig.midi.outputs[Rig.lc6000Out.id]?.sent ?? []).compactMap { if case .noteOn(_, let note, _) = $0 { note } else { nil } })
    }

    @Test("Removed and back in one device change: a held Cue is released once, and every LED is painted again")
    func removedAndBackReconnects() throws {
        let rig = try Rig()
        rig.coordinator.start()
        let painted = Self.ledNotes(rig)
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)   // Cue held
        rig.osc.sent.removeAll()
        rig.midi.outputs[Rig.lc6000Out.id]?.sent.removeAll()
        rig.coordinator.devicesChanged(removed: [Rig.lc6000.id])
        #expect(rig.osc.sent.filter { $0.address.hasSuffix("/Cue") } == [OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)])])
        #expect(Self.ledNotes(rig).isSuperset(of: painted))
        #expect(rig.coordinator.status.controllers.first?.connected == true)
    }
}
