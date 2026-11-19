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
}
