import ControllerBridgeCore
import Foundation
import Testing

/// Feedback liveness (#21). Syndicate sends feedback only when a value changes, so a quiet Syndicate and a gone one
/// look the same. After `osc.feedback_quiet_ms` (10 s) of quiet the bridge sends one Resend: Syndicate answers it with
/// every subscribed value, and always ColorPalette (user guide §14.10). With no answer within `osc.feedback_answer_ms`
/// (2 s), feedback counts as stopped.
@Suite("Feedback liveness")
struct LivenessTests {
    static let resend = OSCMessage("/Syndicate/Feedback/Resend", [.int(1)])

    /// Started at t = 0, with one feedback message at t = 0.5 so feedback is live, and everything sent so far cleared.
    static func liveRig() throws -> Rig {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.5
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.osc.sent.removeAll()
        return rig
    }

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    @Test("After 10 s with no feedback, the bridge asks Syndicate to resend, once")
    func quietSendsOneProbe() throws {
        let rig = try Self.liveRig()
        Self.tick(rig, at: 10.4)
        #expect(rig.osc.sent == [])

        Self.tick(rig, at: 10.5)
        #expect(rig.osc.sent == [Self.resend])

        for time in [10.6, 11.0, 12.0, 12.4] { Self.tick(rig, at: time) }
        #expect(rig.osc.sent == [Self.resend])
    }

    @Test("Any answer within 2 s keeps feedback live: the LEDs stay as they are, and the next probe waits another 10 s")
    func answerKeepsLive() throws {
        let rig = try Self.liveRig()
        Self.tick(rig, at: 10.5)
        rig.clock.now = 11.0
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        for time in [12.6, 15.0, 20.9] { Self.tick(rig, at: time) }

        #expect(rig.leds[1] == 127)
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.osc.sent == [Self.resend])
        Self.tick(rig, at: 21.0)
        #expect(rig.osc.sent == [Self.resend, Self.resend])
    }

    @Test("With no answer within 2 s, feedback is stale: Syndicate's state is cleared, the bridge's own state stays")
    func noAnswerGoesStale() throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.clock.now = 0.5
        for (path, value) in [("Loaded", 1), ("Playing", 1), ("Sync", 1), ("Loop", 1)] {
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [.int(Int32(value))]))
        }
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Cues", [.int(1), .string("Drop")] + Array(repeating: [OSCArgument.int(0), .string("")], count: 7).flatMap { $0 }))
        rig.coordinator.midi(.noteOn(channel: 0, note: 22, velocity: 127), source: Rig.lc6000.id)   // Key Lock on
        // Play, Sync, Master, Loop In, pad 1 (red, 48), ring (11) and Key Lock are lit.
        #expect([rig.leds[1], rig.leds[20], rig.leds[21], rig.leds[8], rig.leds[32], rig.leds[40], rig.leds[22]]
            == [127, 127, 127, 127, 48, 11, 127])

        Self.tick(rig, at: 10.5)
        Self.tick(rig, at: 12.4)
        #expect(rig.coordinator.status.feedback == .live)
        Self.tick(rig, at: 12.5)

        #expect(rig.coordinator.status.feedback == .stale)
        // Syndicate's LEDs go to idle: buttons dim (1), pads and ring off. Key Lock is the bridge's own: still lit.
        #expect([rig.leds[1], rig.leds[20], rig.leds[21], rig.leds[8], rig.leds[32], rig.leds[40], rig.leds[22]]
            == [1, 1, 1, 1, 0, 0, 127])
        #expect(rig.log.lines.contains("Syndicate feedback stopped"))
        #expect(rig.coordinator.status.lastDropout == "Syndicate feedback stopped")
    }

    /// A Coordinator whose mapping sets `leds.stale_idle`, started at t = 0 with Playing 1 at t = 0.5.
    final class StaleIdleRig {
        let midi = Rig.FakeMIDISystem(sources: [Rig.lc6000], destinations: [Rig.lc6000Out])
        let clock = Rig.FakeClock()
        let coordinator: Coordinator

        init(staleIdle: String) throws {
            let override = Data(#"{ "leds": { "stale_idle": "\#(staleIdle)" } }"#.utf8)
            coordinator = Coordinator(
                mapping: try Mapping.bundledDefault(overriddenBy: override),
                midi: midi, osc: Rig.FakeOSC(), clock: clock, log: Rig.FakeLog()
            )
            coordinator.start()
            clock.now = 0.5
            coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        }

        func tick(at time: Double) {
            clock.now = time
            coordinator.tick()
        }

        var leds: [UInt8: UInt8] {
            var out: [UInt8: UInt8] = [:]
            for case let .noteOn(_, note, velocity) in midi.outputs[Rig.lc6000Out.id]?.sent ?? [] { out[note] = velocity }
            return out
        }
    }

    @Test("With stale_idle \"off\", Syndicate's button LEDs go off once stale; the bridge's own unlit LEDs stay dim")
    func staleIdleOff() throws {
        let rig = try StaleIdleRig(staleIdle: "off")
        rig.tick(at: 10.5)
        rig.tick(at: 12.5)
        // Play (1) and Cue (2) follow Syndicate: off. Key Lock (22) and Shift (26) are the bridge's own: still dim.
        #expect([rig.leds[1], rig.leds[2], rig.leds[22], rig.leds[26]] == [0, 0, 1, 1])
    }

    /// Live, then stale at t = 12.5 (probe at 10.5, no answer), with everything sent so far cleared.
    static func staleRig() throws -> Rig {
        let rig = try liveRig()
        tick(rig, at: 10.5)
        tick(rig, at: 12.5)
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("While stale, the bridge asks again every 10 s, so it finds a restarted Syndicate even if nothing changes there")
    func staleProbesEvery10s() throws {
        let rig = try Self.staleRig()
        Self.tick(rig, at: 20.4)
        #expect(rig.osc.sent == [])
        Self.tick(rig, at: 20.5)
        Self.tick(rig, at: 25.0)
        #expect(rig.osc.sent == [Self.resend])
        Self.tick(rig, at: 30.5)
        #expect(rig.osc.sent == [Self.resend, Self.resend])
        #expect(rig.coordinator.status.feedback == .stale)
    }

    @Test("Feedback that answers an open probe while stale is the full state already: back to live, no extra Resend")
    func comebackAnsweringProbe() throws {
        let rig = try Self.staleRig()
        Self.tick(rig, at: 20.5)                 // probe
        rig.clock.now = 21.0
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))

        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.log.lines.contains("Syndicate feedback is back"))
        #expect(rig.leds[1] == 127)
    }

    @Test("Feedback that comes back with no probe open (Syndicate restarted on its own) gets exactly one Resend")
    func comebackUnprompted() throws {
        let rig = try Self.staleRig()
        rig.clock.now = 15.0                     // the last probe, at 10.5, is long past its answer window
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))

        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.log.lines.contains("Syndicate feedback is back"))
    }

    @Test("At launch, start sends one Resend; the first feedback is its answer and doesn't count as coming back")
    func launchFirstFeedback() throws {
        let rig = try Rig()
        rig.coordinator.start()
        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.feedback == .waiting)

        rig.clock.now = 0.3
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        #expect(rig.osc.sent == [Self.resend])
        #expect(rig.coordinator.status.feedback == .live)
        #expect(!rig.log.lines.contains("Syndicate feedback is back"))
    }

    @Test("With no Syndicate at launch, the bridge waits and asks every 10 s; when it finally answers, that's no comeback")
    func launchWithoutSyndicate() throws {
        let rig = try Rig()
        rig.coordinator.start()
        for time in [2.5, 9.9] { Self.tick(rig, at: time) }
        #expect(rig.coordinator.status.feedback == .waiting)
        #expect(rig.osc.sent == [Self.resend])
        Self.tick(rig, at: 10.0)
        Self.tick(rig, at: 20.0)
        #expect(rig.osc.sent == [Self.resend, Self.resend, Self.resend])
        #expect(rig.coordinator.status.lastDropout == nil)

        rig.clock.now = 20.5
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]))
        #expect(rig.coordinator.status.feedback == .live)
        #expect(rig.osc.sent.count == 3)
        #expect(!rig.log.lines.contains("Syndicate feedback is back"))
    }

    @Test("A replug while a probe is open sends no second Resend: one at a time")
    func replugDuringProbe() throws {
        let rig = try Self.liveRig()
        Self.tick(rig, at: 10.5)                 // probe, open until 12.5
        rig.midi.sources = []
        rig.coordinator.devicesChanged()
        rig.midi.sources = [Rig.lc6000]
        rig.clock.now = 11.0
        rig.coordinator.devicesChanged()         // replug: resync, but the probe is still waiting for its answer
        #expect(rig.osc.sent.filter { $0 == Self.resend } == [Self.resend])
    }
}
