import Foundation
@testable import ControllerBridgeCore
import Testing

/// A 7-bit pitch fader on one CC (#195), beside the LC6000's 14-bit pair. Expected values worked by hand.
@Suite("7-bit fader mapping")
struct SevenBitFaderMappingTests {
    @Test("bits is 14 when left out; a 7-bit fader may leave out lsb_cc")
    func decoding() throws {
        let fourteen = #"{ "msb_cc": 8, "lsb_cc": 40, "invert": false, "dead_zone": 0.005 }"#
        let seven = #"{ "bits": 7, "msb_cc": 8, "invert": false, "dead_zone": 0.005 }"#
        #expect(try JSONDecoder().decode(Mapping.Pitch.self, from: Data(fourteen.utf8)).bits == 14)
        let pitch = try JSONDecoder().decode(Mapping.Pitch.self, from: Data(seven.utf8))
        #expect(pitch.bits == 7)
        #expect(pitch.lsbCC == nil)
    }

    @Test("The bundled LC6000 is 14-bit on CC 8 and 40, as before #195")
    func lc6000() throws {
        let pitch = try Mapping.bundledDefault().pitch
        #expect([pitch.bits, pitch.msbCC, pitch.lsbCC] == [14, 8, 40])
    }
}
