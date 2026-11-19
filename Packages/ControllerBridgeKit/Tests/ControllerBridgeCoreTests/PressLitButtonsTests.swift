@testable import ControllerBridgeCore
import Testing

/// The dark buttons (#476): Beat Jump, Track Skip, the browse knob's ring, Vinyl, Pitch Bend and Param have no state to
/// show, so they're lit dim when idle (when the profile dims unlit buttons) and full while held.
@Suite("Press-lit buttons")
struct PressLitButtonsTests {
    /// The LC6000's notes for them: beat jump 3/4, track skip 5/6, the browse press 18, Vinyl 19, pitch bend 24/25,
    /// param 68/69.
    static let notes: [UInt8] = [3, 4, 5, 6, 18, 19, 24, 25, 68, 69]
    static let names = ["beat_jump_back", "beat_jump_forward", "track_prev", "track_next", "select_press", "vinyl",
                        "pitch_minus", "pitch_plus", "param_back", "param_forward"]

    static func started(_ override: String? = nil) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        return rig
    }

    @Test("At start each is dim (1); with dim_unlit_buttons off, off (0)")
    func idle() throws {
        let dim = try Self.started()
        for note in Self.notes { #expect(dim.leds[note] == 1, "note \(note)") }
        let off = try Self.started(#"{ "leds": { "dim_unlit_buttons": false } }"#)
        for note in Self.notes { #expect(off.leds[note] == 0, "note \(note)") }
    }

    @Test("A profile that doesn't name them sends them nothing")
    func unnamed() throws {
        var mapping = try Mapping.bundledDefault()
        for name in Self.names { mapping.notes.buttons[name] = nil }
        let rig = Rig(mapping: mapping)
        rig.coordinator.start()
        for note in Self.notes { #expect(rig.leds[note] == nil, "note \(note)") }
    }
}
