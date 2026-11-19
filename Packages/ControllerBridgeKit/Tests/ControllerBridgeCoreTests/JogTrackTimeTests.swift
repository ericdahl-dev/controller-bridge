@testable import ControllerBridgeCore
import Testing

/// The last minute's warning (#460), the user's pick: in the last 60 s, while playing, the remaining time and the
/// progress ring blink at 1 Hz between red and their normal colors; nothing disappears. `phase` is the time since the
/// shown second last changed, 0 to 1: red in its first half, so the color flips on the frame the digit changes.
@Suite("Jog display: track time warning")
struct JogTrackTimeTests {
    typealias Look = JogTrackTime.Look

    @Test("Playing in the last 60 s: red from each second's change, normal in its second half")
    func blinks() {
        #expect(JogTrackTime.look(elapsed: 90, length: 120, playing: true, phase: 0) == .warningRed)
        #expect(JogTrackTime.look(elapsed: 90, length: 120, playing: true, phase: 0.2) == .warningRed)
        #expect(JogTrackTime.look(elapsed: 90, length: 120, playing: true, phase: 0.7) == .warningNormal)
    }

    @Test("From exactly 60 s left to the end; not at 61")
    func edges() {
        #expect(JogTrackTime.look(elapsed: 60, length: 120, playing: true, phase: 0) == .warningRed)
        #expect(JogTrackTime.look(elapsed: 120, length: 120, playing: true, phase: 0) == .warningRed)
        #expect(JogTrackTime.look(elapsed: 59, length: 120, playing: true, phase: 0) == .normal)
    }

    @Test("Paused, or an unknown length: normal")
    func notWhen() {
        #expect(JogTrackTime.look(elapsed: 90, length: 120, playing: false, phase: 0.2) == .normal)
        #expect(JogTrackTime.look(elapsed: 90, length: 0, playing: true, phase: 0.2) == .normal)
    }

    /// Near red: saturated (the spread at least half the brightest channel) and within 25° of hue of the warning's red
    /// (0xFF3B30, 3.5°). Then the warning's normal half fills white (0xEDEDEA), so the blink still shows.
    static let nearRed: [[Int]] = [[255, 0, 0], [255, 0, 64], [255, 80, 0], [128, 0, 0]]
    static let notNearRed: [[Int]] = [[255, 128, 0], [255, 0, 128], [0, 128, 255], [255, 255, 255], [255, 200, 200]]

    @Test("A deck color near red blinks against white", arguments: nearRed)
    func nearRedIsWhite(deck: [Int]) {
        #expect(JogTrackTime.warningNormalFill(deck: deck) == [0xED, 0xED, 0xEA])
    }

    @Test("Any other deck color blinks against itself", arguments: notNearRed)
    func otherIsItself(deck: [Int]) {
        #expect(JogTrackTime.warningNormalFill(deck: deck) == deck)
    }
}
