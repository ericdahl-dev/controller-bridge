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
}
