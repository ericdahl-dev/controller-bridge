@testable import ControllerBridgeCore
import Testing

/// The last minute's warning (#460), the user's pick: in the last 60 s, while playing, the remaining time and the
/// progress ring turn red and blink at 1 Hz, swapping red and their normal colours; nothing disappears. `phase` is the
/// place in the current second, 0 to 1: red in its first half.
@Suite("Jog display: track time warning")
struct JogTrackTimeTests {
    @Test("Playing in the last 60 s: red in each second's first half, normal in its second")
    func blinks() {
        #expect(JogTrackTime.warning(elapsed: 90, length: 120, playing: true, phase: 0.2))
        #expect(!JogTrackTime.warning(elapsed: 90, length: 120, playing: true, phase: 0.7))
    }

    @Test("From exactly 60 s left to the end; not at 61")
    func edges() {
        #expect(JogTrackTime.warning(elapsed: 60, length: 120, playing: true, phase: 0))
        #expect(JogTrackTime.warning(elapsed: 120, length: 120, playing: true, phase: 0))
        #expect(!JogTrackTime.warning(elapsed: 59, length: 120, playing: true, phase: 0))
    }

    @Test("Paused, or an unknown length: never red")
    func notWhen() {
        #expect(!JogTrackTime.warning(elapsed: 90, length: 120, playing: false, phase: 0.2))
        #expect(!JogTrackTime.warning(elapsed: 90, length: 0, playing: true, phase: 0.2))
    }
}
