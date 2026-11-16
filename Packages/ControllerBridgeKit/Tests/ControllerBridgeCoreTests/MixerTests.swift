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

    // MARK: Faders and knobs (#207), at the Coordinator seam: the LC6000 plus a DDJ-400-like mixer, test-only

    static func started() throws -> Rig {
        let rig = try Rig(override: section)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func cc(_ rig: Rig, _ controller: UInt8, _ value: UInt8) {
        rig.coordinator.midi(.controlChange(channel: 0, controller: controller, value: value), source: Rig.lc6000.id)
    }

    static func mixer(_ path: String, _ value: Float, channel: Int = 1) -> OSCMessage {
        OSCMessage("/Syndicate/Mixer/" + (path.hasPrefix("filter") ? path.replacingOccurrences(of: "N", with: "\(channel)") : "CH\(channel)/" + path),
                   [.float(value)])
    }

    @Test("A 7-bit fader sends 0..1, with 64 exactly 0.5 (the split rule of the 7-bit pitch fader)")
    func sevenBit() throws {
        let rig = try Self.started()
        for value: UInt8 in [0, 1, 64, 126, 127] { Self.cc(rig, 19, value) }
        #expect(rig.osc.sent == [
            Self.mixer("Volume", 0), Self.mixer("Volume", 0.00781), Self.mixer("Volume", 0.5),
            Self.mixer("Volume", 0.99206), Self.mixer("Volume", 1),
        ])
    }

    @Test("A 14-bit knob sends when its LSB arrives, 8192 exactly 0.5; trim, EQ and filter each to their own address")
    func fourteenBitAndAddresses() throws {
        let rig = try Self.started()
        Self.cc(rig, 7, 64); Self.cc(rig, 39, 0)
        Self.cc(rig, 7, 127); Self.cc(rig, 39, 127)
        Self.cc(rig, 4, 64); Self.cc(rig, 11, 64); Self.cc(rig, 15, 0); Self.cc(rig, 23, 127)
        #expect(rig.osc.sent == [
            Self.mixer("EQ/High", 0.5), Self.mixer("EQ/High", 1),
            Self.mixer("Trim", 0.5), Self.mixer("EQ/Mid", 0.5), Self.mixer("EQ/Low", 0), Self.mixer("filterN.cut", 1),
        ])
    }

    @Test("The mixer channel is the deck the controller drives: on deck 2, the fader moves channel 2")
    func channelFollowsDeck() throws {
        let rig = try Self.started()
        rig.coordinator.setDeck(2, controller: 0)
        rig.osc.sent.removeAll()
        Self.cc(rig, 19, 127)
        #expect(rig.osc.sent.last == Self.mixer("Volume", 1, channel: 2))
    }

    @Test("The LC6000, with no mixer section, sends nothing for those CCs")
    func lc6000Unchanged() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        for controller: UInt8 in [19, 4, 7, 39, 11, 15, 23] { Self.cc(rig, controller, 100) }
        #expect(rig.osc.sent == [])
    }
}
