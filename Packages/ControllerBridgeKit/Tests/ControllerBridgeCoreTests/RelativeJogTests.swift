import Foundation
@testable import ControllerBridgeCore
import Testing

/// A jog that sends relative ticks on one CC (#204), as most Pioneer DDJ platters do, beside the LC6000's absolute
/// 14-bit position. Expected values are worked by hand.
@Suite("Relative jog mapping")
struct RelativeJogMappingTests {
    static let relativeJog = #"""
    { "relative_cc": 33, "relative_edge_cc": 34, "counts_per_rev": 720, "bend_release_ms": 80,
      "seek_seconds_per_rev": 2.0, "beats_per_rev": 4, "require_touch": false }
    """#

    @Test("A jog with relative_cc is relative, and may leave out the 14-bit pair")
    func relative() throws {
        let jog = try JSONDecoder().decode(Mapping.Jog.self, from: Data(Self.relativeJog.utf8))
        #expect(jog.mode == .relative(cc: 33, edgeCC: 34))
    }

    @Test("The LC6000's jog is the absolute 14-bit pair on CC 17 and 49, as before #204")
    func lc6000Absolute() throws {
        #expect(try Mapping.bundledDefault().jog.mode == .absolute(msbCC: 17, lsbCC: 49))
    }
}

/// The Coordinator seam (#204): a test-only profile whose platter sends offset-64 ticks on CC 33 (the top) and CC 34
/// (the edge), 720 ticks a turn. CC 33 and 34 are free in the LC6000 mapping.
@Suite("Relative jog at the Coordinator")
struct RelativeJogCoordinatorTests {
    static let profile = #"""
    { "midi": { "encoder_format": "offset_64" },
      "jog": { "relative_cc": 33, "relative_edge_cc": 34, "counts_per_rev": 720, "seek_seconds_per_rev": 4, "beats_per_rev": 4 } }
    """#

    static func started(_ override: String = profile) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func turn(_ rig: Rig, cc: UInt8 = 33, _ value: UInt8) {
        rig.coordinator.midi(.controlChange(channel: 0, controller: cc, value: value), source: Rig.lc6000.id)
    }

    static func playing(_ rig: Rig) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
    }

    @Test("Playing, a forward tick (0x41) nudges forward; a back tick (0x3F) turns the nudge around")
    func nudge() throws {
        let rig = try Self.started()
        Self.playing(rig)
        Self.turn(rig, 0x41)
        Self.turn(rig, 0x42)
        Self.turn(rig, 0x3F)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(-1)]),
        ])
    }

    @Test("Playing, PhaseBend 0 follows bend_release_ms (80) after the last tick")
    func release() throws {
        let rig = try Self.started()
        Self.playing(rig)
        Self.turn(rig, 0x41)
        rig.clock.now = 0.05
        rig.coordinator.tick()
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)])])
        rig.clock.now = 0.2
        rig.coordinator.tick()
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]),
        ])
    }
}
