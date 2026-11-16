import ControllerBridgeCore
import Foundation
import Testing

/// The mixer section (#207): channel faders, trim, EQ, filter, cue/mute/solo and VU meters, for controllers that have
/// one. Optional: the LC6000 has none.
@Suite("Mixer")
struct MixerTests {
    static let section = #"""
        { "mixer": {
            "volume": { "msb_cc": 19, "bits": 7 },
            "trim": { "msb_cc": 4, "bits": 7 },
            "eq_high": { "msb_cc": 7, "lsb_cc": 39 },
            "eq_mid": { "msb_cc": 11, "bits": 7 },
            "eq_low": { "msb_cc": 15, "bits": 7 },
            "filter": { "msb_cc": 23, "bits": 7 },
            "cue_note": 84, "mute_note": 85, "solo_note": 86,
            "meter": { "cc": 2, "steps": [0, 16, 32, 48, 64, 80, 96, 112], "clip": 127, "hold_ms": 300, "rate_hz": 30 },
            "pickup": true, "pickup_tolerance": 0.03
        } }
        """#

    @Test("The LC6000 has no mixer, and loads as before")
    func lc6000HasNone() throws {
        #expect(try Mapping.bundledDefault().mixer == nil)
    }

    @Test("A mixer section reads its controls: 7-bit as one CC, 14-bit as a pair; unset ones are nil")
    func decodes() throws {
        let mixer = try #require(try Mapping.bundledDefault(overriddenBy: Data(Self.section.utf8)).mixer)
        #expect(mixer.volume == Mapping.Control(bits: 7, msbCC: 19, lsbCC: nil))
        #expect(mixer.eqHigh == Mapping.Control(bits: 14, msbCC: 7, lsbCC: 39))
        #expect(mixer.filterRes == nil)
        #expect(mixer.cueNote == 84)
        #expect(mixer.muteNote == 85)
        #expect(mixer.meter == Mapping.Mixer.Meter(cc: 2, steps: [0, 16, 32, 48, 64, 80, 96, 112], clip: 127, holdMs: 300, rateHz: 30))
        #expect(mixer.pickup)
        #expect(mixer.pickupTolerance == 0.03)
    }

    @Test("Meter's hold, rate and clip, and pickup, have defaults")
    func defaults() throws {
        let json = #"{ "mixer": { "meter": { "cc": 2, "steps": [0, 64, 127] } } }"#
        let mixer = try #require(try Mapping.bundledDefault(overriddenBy: Data(json.utf8)).mixer)
        #expect(mixer.meter == Mapping.Mixer.Meter(cc: 2, steps: [0, 64, 127], clip: nil, holdMs: 300, rateHz: 30))
        #expect(mixer.pickup)
        #expect(mixer.pickupTolerance == 0.02)
    }

    @Test("A 14-bit control needs its LSB, as the pitch fader does")
    func fourteenBitNeedsLSB() {
        #expect(throws: MappingError.invalid(["mixer.volume: lsb_cc is missing (or set bits to 7)"])) {
            try Mapping.bundledDefault(overriddenBy: Data(#"{ "mixer": { "volume": { "msb_cc": 19 } } }"#.utf8))
        }
    }
}
