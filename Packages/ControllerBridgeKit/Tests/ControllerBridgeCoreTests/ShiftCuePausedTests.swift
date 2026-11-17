import Foundation
@testable import ControllerBridgeCore
import Testing

/// Shift + hot cue pad on a stopped deck goes to the cue, paused (#358): Cue<n>, then Playing 0 the moment Syndicate
/// reports Playing 1. Syndicate has no jump-without-play input, and a pause sent before the launch cancels the jump
/// (the live check on #358). The LC6000 rig: Shift is note 26, pad 1 is note 32, all on channel 1.
@Suite("Shift + hot cue pad on a stopped deck")
struct ShiftCuePausedTests {
    static func started(_ override: String? = nil) throws -> Rig {
        let rig = try PadChannelCoordinatorTests.started(override)
        feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
        return rig
    }

    static func feed(_ rig: Rig, _ name: String, _ value: Int32) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + name, [.int(value)]))
    }

    static func shift(_ rig: Rig, _ down: Bool) {
        rig.coordinator.midi(down ? .noteOn(channel: 0, note: 26, velocity: 127) : .noteOff(channel: 0, note: 26, velocity: 0),
                             source: Rig.lc6000.id)
    }

    /// Shift held, pad `note` pressed and released, Shift let go.
    static func shiftPad(_ rig: Rig, _ note: UInt8 = 32) {
        shift(rig, true)
        PadChannelCoordinatorTests.press(rig, note, channel: 1)
        shift(rig, false)
    }

    static let cue1 = OSCMessage("/Syndicate/Deck/1/Cue1", [.int(1)])
    static let pause = OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)])

    @Test("Stopped: Shift + pad 1 sends Cue1, never HotCue; the Playing 1 that follows gets one Playing 0")
    func stopped() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        #expect(rig.osc.sent == [Self.cue1])
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [Self.pause])
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 0)
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [], "only the launch the pad started is paused")
    }

    @Test("Q on (PlayPending 1 before Playing 1): no pause; the user hears the cue, as a normal hot cue")
    func quantizeOnPlays() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        rig.osc.sent.removeAll()
        Self.feed(rig, "PlayPending", 1)
        Self.feed(rig, "Playing", 1)
        Self.feed(rig, "PlayPending", 0)
        #expect(rig.osc.sent == [])
    }
}
