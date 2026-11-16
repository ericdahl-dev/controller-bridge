import LC6000Core
import Testing

/// Browse, loop and jump controls (#16). Expected OSC is from the Python bridge (lc6000_bridge/bridge.py), note and
/// CC numbers are from the default mapping (Play 1 … Param ▶ 69, select turn CC 6, auto loop size CC 3).
@Suite("Browse, loops and jumps")
struct BrowseTests {
    /// A started rig with the start-up Resend cleared, so only what the test does is left.
    static func startedRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func press(_ rig: Rig, _ note: UInt8) {
        rig.coordinator.midi(.noteOn(channel: 0, note: note, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOff(channel: 0, note: note, velocity: 0), source: Rig.lc6000.id)
    }

    @Test("Track ◀ and ▶ move the browser up and down, on press only")
    func trackButtons() throws {
        let rig = try Self.startedRig()
        Self.press(rig, 5)
        Self.press(rig, 6)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Browser/Up", [.int(1)]),
            OSCMessage("/Syndicate/Browser/Down", [.int(1)]),
        ])
    }

    @Test("Back goes back in the browser and Forward enters, on press only")
    func backAndForward() throws {
        let rig = try Self.startedRig()
        Self.press(rig, 16)
        Self.press(rig, 17)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Browser/Back", [.int(1)]),
            OSCMessage("/Syndicate/Browser/Enter", [.int(1)]),
        ])
    }
}
