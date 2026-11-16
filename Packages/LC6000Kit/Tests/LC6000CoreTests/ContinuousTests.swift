import Foundation
import LC6000Core
import Testing

/// Pitch fader, jog and Needle Drop. Expected values come from the Python bridge's tests and codec.
@Suite("Continuous controls")
struct ContinuousTests {
    static func started(_ override: String? = nil) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func cc(_ rig: Rig, _ controller: UInt8, _ value: UInt8) {
        rig.coordinator.midi(.controlChange(channel: 0, controller: controller, value: value), source: Rig.lc6000.id)
    }

    @Test("The 14-bit pitch fader sends TempoSlider as a float; a repeated value isn't resent")
    func pitchFader14Bit() throws {
        let rig = try Self.started()
        Self.cc(rig, 8, 0x7F)
        Self.cc(rig, 40, 0x7F)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(1.0)]))
        let count = rig.osc.sent.count
        Self.cc(rig, 40, 0x7F)
        #expect(rig.osc.sent.count == count)
    }

    @Test("Fader bottom is -1.0; the center (0x40/0x00) snaps to 0.0 inside the dead zone")
    func pitchEndsAndCenter() throws {
        let rig = try Self.started()
        Self.cc(rig, 8, 0x40)
        Self.cc(rig, 40, 0x00)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(0.0)]))
        Self.cc(rig, 8, 0x00)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(-1.0)]))
    }

    @Test("pitch.invert flips the direction: fader top sends -1.0")
    func pitchInvert() throws {
        let rig = try Self.started(#"{ "pitch": { "invert": true } }"#)
        Self.cc(rig, 8, 0x7F)
        Self.cc(rig, 40, 0x7F)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(-1.0)]))
    }

    static func feedback(_ rig: Rig, _ path: String, _ arguments: [OSCArgument]) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, arguments))
    }

    @Test("While playing, the jog nudges with PhaseBend ±1, and PhaseBend 0 follows 80 ms after the wheel stops")
    func jogBendThenRelease() throws {
        let rig = try Self.started()
        Self.feedback(rig, "Playing", [.int(1)])
        Self.cc(rig, 55, 0x03)
        Self.cc(rig, 55, 0x02)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)])])
        Self.cc(rig, 55, 0x7E)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(-1)]))

        rig.clock.now = 0.05
        rig.coordinator.tick()
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(-1)]))

        rig.clock.now = 0.2
        rig.coordinator.tick()
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]))
        #expect(rig.osc.sent.count == 3)
    }

    @Test("The nudge is a held control: stop sends PhaseBend 0 once, and the next turn nudges afresh")
    func bendIsHeld() throws {
        let rig = try Self.started()
        Self.feedback(rig, "Playing", [.int(1)])
        Self.cc(rig, 55, 0x01)
        rig.osc.sent.removeAll()

        rig.coordinator.stop()
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)])])

        Self.cc(rig, 55, 0x01)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)]))

        rig.osc.sent.removeAll()
        rig.coordinator.stop()
        rig.clock.now = 1
        rig.coordinator.tick()
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)])])
    }

    @Test("Syndicate reporting Playing 0 ends the nudge with PhaseBend 0")
    func stopPlayingEndsBend() throws {
        let rig = try Self.started()
        Self.feedback(rig, "Playing", [.int(1)])
        Self.cc(rig, 55, 0x01)
        Self.feedback(rig, "Playing", [.int(0)])
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]))
        #expect(rig.osc.sent.count == 2)
    }

    @Test("Letting go of the platter ends the nudge with PhaseBend 0")
    func platterReleaseEndsBend() throws {
        let rig = try Self.started()
        Self.feedback(rig, "Playing", [.int(1)])
        rig.coordinator.midi(.noteOn(channel: 0, note: 40, velocity: 127), source: Rig.lc6000.id)
        Self.cc(rig, 55, 0x01)
        rig.coordinator.midi(.noteOff(channel: 0, note: 40, velocity: 0), source: Rig.lc6000.id)
        #expect(rig.osc.sent == [
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]),
        ])
    }

    @Test("While paused, the jog moves the playhead: 10 ticks × 0.02 s over a 200 s track from 0.5 seeks to 0.501")
    func jogSeeksWhilePaused() throws {
        let rig = try Self.started()
        Self.feedback(rig, "TrackInfo", [.string("t"), .string("a"), .string("8A"), .float(120), .float(200), .int(100), .int(400), .string("track")])
        Self.feedback(rig, "Progress", [.float(0.5)])
        Self.cc(rig, 55, 10)
        guard case .float(let position)? = rig.osc.sent.last?.arguments.first else {
            Issue.record("expected a float WaveformSeek, got \(rig.osc.sent)")
            return
        }
        #expect(rig.osc.sent.last?.address == "/Syndicate/Deck/1/WaveformSeek")
        #expect(abs(position - 0.501) < 0.000_01)
    }

    @Test("Paused with no track length, 32 jog ticks skip one beat")
    func jogFallsBackToBeatSkip() throws {
        let rig = try Self.started()
        for _ in 0..<4 { Self.cc(rig, 55, 0x08) }
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/BeatSkip", [.int(1)])])
        for _ in 0..<4 { Self.cc(rig, 55, 0x78) }   // 4 × -8 ticks: one beat back
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/BeatSkip", [.int(-1)]))
        #expect(rig.osc.sent.count == 2)
    }

    @Test("Needle Drop seeks only while the strip is touched: 127 seeks to the end")
    func needleSeeksWhileTouched() throws {
        let rig = try Self.started()
        Self.cc(rig, 64, 64)
        #expect(rig.osc.sent == [])
        rig.coordinator.midi(.noteOn(channel: 0, note: 70, velocity: 127), source: Rig.lc6000.id)
        Self.cc(rig, 64, 127)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/WaveformSeek", [.float(1.0)])])
        rig.coordinator.midi(.noteOff(channel: 0, note: 70, velocity: 0), source: Rig.lc6000.id)
        Self.cc(rig, 64, 0)
        #expect(rig.osc.sent.count == 1)
    }

    @Test("Release-all clears the needle touch: after stop, moving the strip seeks nothing")
    func releaseAllClearsNeedleTouch() throws {
        let rig = try Self.started()
        rig.coordinator.midi(.noteOn(channel: 0, note: 70, velocity: 127), source: Rig.lc6000.id)
        rig.coordinator.stop()
        Self.cc(rig, 64, 100)
        #expect(rig.osc.sent == [])
    }

    @Test("With jog.require_touch, the jog acts only while the platter is touched, and release-all clears the touch")
    func releaseAllClearsPlatterTouch() throws {
        let rig = try Self.started(#"{ "jog": { "require_touch": true } }"#)
        Self.feedback(rig, "Playing", [.int(1)])
        Self.cc(rig, 55, 0x01)
        #expect(rig.osc.sent == [])

        rig.coordinator.midi(.noteOn(channel: 0, note: 40, velocity: 127), source: Rig.lc6000.id)
        Self.cc(rig, 55, 0x01)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(1)])])

        rig.coordinator.stop()
        rig.osc.sent.removeAll()
        Self.cc(rig, 55, 0x01)
        #expect(rig.osc.sent == [])
    }

    @Test("The pitch center LED is full while the last tempo sent is 0.0, and off otherwise")
    func pitchCenterLED() throws {
        let rig = try Self.started()
        #expect(rig.leds[42] == 0)
        Self.cc(rig, 8, 0x40)
        Self.cc(rig, 40, 0x00)
        #expect(rig.leds[42] == 127)
        Self.cc(rig, 8, 0x50)
        #expect(rig.leds[42] == 0)
    }

    @Test("Loaded 0 forgets the track's progress and length: a paused jog then falls back to BeatSkip")
    func unloadForgetsTrack() throws {
        let rig = try Self.started()
        Self.feedback(rig, "Loaded", [.int(1)])
        Self.feedback(rig, "TrackInfo", [.string("t"), .string("a"), .string("8A"), .float(120), .float(200), .int(100), .int(400), .string("track")])
        Self.feedback(rig, "Progress", [.float(0.5)])
        Self.feedback(rig, "Loaded", [.int(0)])
        for _ in 0..<4 { Self.cc(rig, 55, 0x08) }
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/BeatSkip", [.int(1)])])
    }
}
