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
