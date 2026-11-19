import Foundation
@testable import ControllerBridgeCore
import Testing

/// VINYL toggles what the jog does on a playing deck (#540, the owner's pick): off (the default), it bends the tempo
/// (PhaseBend), as before; on, it moves through the track (WaveformSeek), as the paused jog does, with the same step
/// and the same quantize hold, so Syndicate doesn't snap each move to the grid. Syndicate has no scratch input: this
/// seeks.
@Suite("VINYL: the playing jog bends or seeks")
struct VinylSeekTests {
    typealias Q = JogQuantizeTests

    static func vinyl(_ rig: Rig) {
        rig.coordinator.midi(.noteOn(channel: 0, note: 19, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.midi(.noteOff(channel: 0, note: 19, velocity: 0), source: Rig.lc6000.id)
    }

    /// The paused rig from JogQuantizeTests, now playing.
    static func playing() throws -> Rig {
        let rig = try Q.paused()
        ContinuousTests.feedback(rig, "Playing", [.int(1)])
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("VINYL on: a playing deck's jog seeks, quantize held at None first, as the paused jog does")
    func onSeeks() throws {
        let rig = try Self.playing()
        Self.vinyl(rig)
        rig.osc.sent.removeAll()
        rig.clock.now = 10
        ContinuousTests.platterAt(rig, 2100)
        #expect(Q.addresses(rig) == ["/Syndicate/Deck/1/Quantize", "/Syndicate/Deck/1/WaveformSeek"])
        #expect(rig.osc.sent.first == Q.quantizeNone)
    }

    @Test("The same step as the paused jog: 100 counts of 1000 a turn, 4 s a turn, on 200 s from halfway is 0.502")
    func sameStep() throws {
        let rig = try Self.playing()
        Self.vinyl(rig)
        rig.osc.sent.removeAll()
        ContinuousTests.platterAt(rig, 2100)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/WaveformSeek", [.float(0.502)]))
    }

    @Test("A second VINYL press turns it off: the playing jog bends again")
    func offBends() throws {
        let rig = try Self.playing()
        Self.vinyl(rig)
        Self.vinyl(rig)
        rig.osc.sent.removeAll()
        ContinuousTests.platterAt(rig, 2100)
        #expect(Q.addresses(rig) == ["/Syndicate/Deck/1/PhaseBend"])
    }

    @Test("A paused deck's jog is the same in both modes: it seeks, quantize held")
    func pausedUnchanged() throws {
        for presses in [0, 1] {
            let rig = try Q.paused()
            for _ in 0..<presses { Self.vinyl(rig) }
            rig.osc.sent.removeAll()
            ContinuousTests.platterAt(rig, 2100)
            #expect(Q.addresses(rig) == ["/Syndicate/Deck/1/Quantize", "/Syndicate/Deck/1/WaveformSeek"])
            #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/WaveformSeek", [.float(0.502)]))
        }
    }

    @Test("Turning seek on mid-bend ends the bend")
    func onEndsBend() throws {
        let rig = try Self.playing()
        ContinuousTests.platterAt(rig, 2100)
        #expect(Q.addresses(rig) == ["/Syndicate/Deck/1/PhaseBend"])
        rig.osc.sent.removeAll()
        Self.vinyl(rig)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)])])
    }
}
