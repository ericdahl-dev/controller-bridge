@testable import ControllerBridgeCore
import Testing

/// The level meter's scale (#582). Syndicate's raw channel level goes above 1.0 (+2.6 dB seen) while its own meter stays
/// out of the red, "near the top" on a loud passage. So the drawn meter is in decibels, from `floorDB` (empty) to
/// `topDB` (full, the red at clip): −36 to +6 dB. Expected values worked out by hand: (20·log10(v) + 36) / 42.
@Suite("Meter scale")
struct MeterScaleTests {
    @Test("−36 dB to +6 dB: the range's two named constants")
    func range() {
        #expect(MeterScale.floorDB == -36)
        #expect(MeterScale.topDB == 6)
    }

    @Test("Where levels land, on 0-127: 0 dB 109, +2.6 dB (the loudest seen) 117, −6.9 dB (the median) 88, −20 dB 48")
    func positions() {
        func shown(_ value: Double) -> Int { Int((MeterScale.position(value) * 127).rounded()) }
        #expect(shown(1.0) == 109)
        #expect(shown(1.349) == 117)
        #expect(shown(0.451) == 88)
        #expect(shown(0.1) == 48)
        #expect(shown(0.5) == 91)
    }

    @Test("Full (the red) only from +6 dB; silence, −36 dB and below, empty")
    func ends() {
        #expect(MeterScale.position(1.996) == 1)
        #expect(MeterScale.position(2.5) == 1)
        #expect(MeterScale.position(1.9) < 1)
        #expect(MeterScale.position(0.0158) == 0)
        #expect(MeterScale.position(0) == 0)
        #expect(MeterScale.position(-1) == 0)
    }
}
