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

/// The 7-bit tempo mapping (#195): 64 is the exact center, so a centered fader reads 0. Below it each step is 1/64,
/// above it 1/63, so 0 and 127 reach -1 and +1.
@Suite("7-bit tempo")
struct SevenBitTempoTests {
    @Test("0, 32, 64, 96, 127 read -1, -0.5, 0, 0.507937, +1")
    func table() {
        let values = [0, 32, 64, 96, 127].map { tempoSlider(from7Bit: UInt8($0), invert: false, deadZone: 0) }
        #expect(values.map { ($0 * 1_000_000).rounded() / 1_000_000 } == [-1, -0.5, 0, 0.507937, 1])
    }

    @Test("invert flips it; within the dead zone it snaps to 0")
    func invertAndDeadZone() {
        #expect(tempoSlider(from7Bit: 0, invert: true, deadZone: 0) == 1)
        #expect(tempoSlider(from7Bit: 65, invert: false, deadZone: 0.02) == 0)   // 1/63 = 0.0159, inside 0.02
        #expect(tempoSlider(from7Bit: 66, invert: false, deadZone: 0.02) == 2.0 / 63)
    }
}
