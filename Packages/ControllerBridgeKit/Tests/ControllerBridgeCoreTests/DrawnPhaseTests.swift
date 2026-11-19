@testable import ControllerBridgeCore
import Testing

/// The phase rule's value on the wire (#462), from a deck's PhaseOffset in beats: -8192 unknown, 0 in phase, else
/// 1/16384 beats, negative behind. The host owns the hysteresis and the wrap guard, so the chip and the renderer draw
/// each value as it is.
@Suite("Drawn display: the phase value")
struct DrawnPhaseTests {
    @Test("Unknown while the deck isn't playing or no offset has come")
    func unknown() {
        var phase = DrawnPhase()
        #expect(phase.value(offset: nil, playing: true) == -8192)
        #expect(phase.value(offset: 0.01, playing: false) == -8192)
    }

    @Test("Off phase, the offset in 1/16384 beats, rounded once, clamped to ±8191 (-8192 is unknown)",
          arguments: [(-0.04, -655), (0.01, 164), (0.0101, 165), (0.4999, 8190), (0.5, 8191), (-0.5, -8191)])
    func measured(offset: Double, wire: Int) {
        var phase = DrawnPhase()
        #expect(phase.value(offset: offset, playing: true) == wire)
    }

    /// The values in turn for a run of offsets, all while playing.
    static func run(_ offsets: [Double], from start: DrawnPhase = DrawnPhase()) -> [Int] {
        var phase = start
        return offsets.map { phase.value(offset: $0, playing: true) }
    }

    @Test("In phase is entered under 0.002 of a beat and left only over 0.004, so the tick doesn't flicker at the edge")
    func hysteresis() {
        // 0.003 is off phase coming in, in phase once in (until it passes 0.004); behind the same.
        #expect(Self.run([0.003, 0.0019, 0.003, 0.0039, 0.0041]) == [49, 0, 0, 0, 67])
        #expect(Self.run([-0.003, -0.001, -0.004, -0.0045]) == [-49, 0, 0, -74])
    }

    @Test("Stopping forgets in phase: playing again starts outside it")
    func stoppingForgets() {
        var phase = DrawnPhase()
        #expect(phase.value(offset: 0.001, playing: true) == 0)
        #expect(phase.value(offset: 0.003, playing: false) == -8192)
        #expect(phase.value(offset: 0.003, playing: true) == 49)
    }
}
