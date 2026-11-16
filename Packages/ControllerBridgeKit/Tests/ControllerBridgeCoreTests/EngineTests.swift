import ControllerBridgeCore
import Testing

/// The Engine is the one consumer loop: events go in through an EventPipe, and the Rig's fakes show what came out.
@Suite("Engine")
struct EngineTests {
    @Test("A Play press from the pipe reaches Syndicate as PlayPause 1")
    func midiFromThePipeReachesTheCoordinator() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        let pipe = EventPipe()

        pipe.producer.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
    }

    @Test("A Playing 1 datagram from the pipe is decoded and lights the Play LED full")
    func udpFromThePipeIsDecodedAsFeedback() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        let pipe = EventPipe()

        // "/Syndicate/Deck/1/Playing" is 25 bytes, + NUL = 26, padded to 28. Then ",i" + 2 NULs, then int32 1.
        pipe.producer.udp(OSCCodecTests.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f506c 6179696e 67000000
            2c690000
            00000001
            """))
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.leds[1] == 127)
    }

    @Test("A datagram that isn't OSC is logged and dropped, and the events after it still arrive")
    func badDatagramIsLoggedAndTheLoopGoesOn() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        let pipe = EventPipe()

        pipe.producer.udp([0x00, 0x01, 0x02]) // 3 bytes: not a whole OSC message
        pipe.producer.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.log.lines.filter { $0.hasPrefix("Dropped a feedback datagram") }.count == 1)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
    }

    @Test("A tick from the pipe reaches the Coordinator: the jog nudge is released after the wheel stops")
    func tickFromThePipeReachesTheCoordinator() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.midi(.controlChange(channel: 0, controller: 55, value: 0x7E), source: Rig.lc6000.id)
        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(-1)]))
        rig.clock.now = 0.2
        let pipe = EventPipe()

        pipe.producer.tick()
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PhaseBend", [.int(0)]))
    }

    @Test("A devices-changed event from the pipe connects a controller that appeared")
    func devicesChangedFromThePipe() async throws {
        let rig = try Rig()
        rig.midi.sources = []
        rig.midi.destinations = []
        rig.coordinator.start()
        rig.midi.sources = [Rig.lc6000]
        rig.midi.destinations = [Rig.lc6000Out]
        let pipe = EventPipe()

        pipe.producer.devicesChanged()
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.midi.connected == [Rig.lc6000.id])
    }

    @Test("Sleep from the pipe releases a held Cue; wake re-checks the devices")
    func sleepAndWakeFromThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)
        rig.osc.sent.removeAll()
        let pipe = EventPipe()

        pipe.producer.sleep()
        pipe.producer.wake()
        pipe.producer.finish()
        rig.midi.sources = []
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)])])
        #expect(rig.midi.connected == [])
    }
}
