import Foundation
@testable import ControllerBridgeCore
import Testing

/// The pitch arrows (#475): while the pitch fader waits to meet Syndicate's tempo (pickup), the arrow pointing the way
/// to move it is lit. "Back" lights to move the fader toward a lower raw value, "forward" toward a higher one; which
/// physical arrow is which is the profile's (#480).
@Suite("Pitch arrows")
struct PitchArrowTests {
    @Test("Two optional LED keys name the arrows: the LC6000's are 41 (back) and 43 (forward); left out, there are none")
    func keys() throws {
        let lc6000 = try Mapping.bundledDefault()
        #expect(lc6000.leds.pitchArrowBack == 41)
        #expect(lc6000.leds.pitchArrowForward == 43)
        #expect(ProfileKeys.key("leds.pitch_arrow_back")?.range == 0...127)
        #expect(ProfileKeys.key("leds.pitch_arrow_forward")?.range == 0...127)
        var leds = lc6000.leds
        leds.pitchArrowBack = nil
        leds.pitchArrowForward = nil
        let decoded = try JSONDecoder().decode(Mapping.LEDs.self, from: JSONEncoder().encode(leds))
        #expect(decoded.pitchArrowBack == nil && decoded.pitchArrowForward == nil)
    }

    static func problems(_ leds: String) -> [String] { Mapping.problems(in: Data(#"{"leds": \#(leds)}"#.utf8)) }

    @Test("The check refuses an arrow on a note another light uses: the center light, the ring, the other arrow, a button")
    func noteAnotherLightUses() {
        #expect(Self.problems(#"{"pitch_arrow_back": 42}"#) == ["leds.pitch_arrow_back: note 42 is also leds.pitch_center"])
        #expect(Self.problems(#"{"pitch_arrow_forward": 40}"#) == ["leds.pitch_arrow_forward: note 40 is also leds.ring and notes.platter_touch"])
        #expect(Self.problems(#"{"pitch_arrow_forward": 41}"#) == ["leds.pitch_arrow_forward: note 41 is also leds.pitch_arrow_back"])
        #expect(Self.problems(#"{"pitch_arrow_back": 1}"#) == ["leds.pitch_arrow_back: note 1 is also notes.play"])
        #expect(Self.problems(#"{"pitch_arrow_back": 128}"#).count == 1)   // range-checked
        #expect(Self.problems(#"{"pitch_arrow_back": 44, "pitch_arrow_forward": 45}"#) == [])
    }

    static let back: UInt8 = 41, forward: UInt8 = 43

    /// The fader at a raw 14-bit position: the MSB, then the LSB, as the LC6000 sends them.
    static func fader(_ rig: Rig, _ raw: Int) {
        ContinuousTests.cc(rig, 8, UInt8(raw >> 7))
        ContinuousTests.cc(rig, 40, UInt8(raw & 0x7F))
    }

    /// A loaded deck whose tempo Syndicate reports as `tempo` (not the bridge's echo): pickup is pending.
    static func pending(tempo: Float = 0.5) throws -> Rig {
        let rig = try ContinuousTests.started()
        ContinuousTests.feedback(rig, "Loaded", [.int(1)])
        ContinuousTests.feedback(rig, "TempoSlider", [.float(tempo)])
        return rig
    }

    @Test("Pickup pending, the fader below Syndicate's value: forward full, back off; above it: back full, forward off")
    func arrowPointsTheWay() throws {
        let rig = try Self.pending()
        Self.fader(rig, 0x2000)   // well below +0.5
        #expect(rig.leds[Self.forward] == 127 && rig.leds[Self.back] == 0)
        #expect(rig.osc.sent.filter { $0.address.hasSuffix("TempoSlider") }.isEmpty)   // still waiting
        let other = try Self.pending(tempo: -0.5)
        Self.fader(other, 0x3000)   // above -0.5
        #expect(other.leds[Self.back] == 127 && other.leds[Self.forward] == 0)
    }

    @Test("pitch.invert: the arrows follow the raw fader, not the tempo. Low raw is a high tempo here, so it must go up: forward")
    func invertFlips() throws {
        let rig = try ContinuousTests.started(#"{"pitch": {"invert": true}}"#)
        ContinuousTests.feedback(rig, "Loaded", [.int(1)])
        ContinuousTests.feedback(rig, "TempoSlider", [.float(0.5)])
        Self.fader(rig, 0x0800)   // raw near the bottom: tempo near +1 inverted, above +0.5
        #expect(rig.leds[Self.forward] == 127 && rig.leds[Self.back] == 0)
    }
}
