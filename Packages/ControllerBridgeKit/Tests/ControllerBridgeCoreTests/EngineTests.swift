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

    @Test("Stop from the pipe releases held controls before run() returns, and events after it are not handled")
    func stopFromThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)   // Cue held
        rig.osc.sent.removeAll()
        let pipe = EventPipe()

        pipe.producer.stop()
        pipe.producer.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)    // after quit: dropped
        // No finish(): stop alone ends the loop.
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)])])
        #expect(rig.midi.connected == [])
    }

    @Test("The status sink gets the Coordinator status once per change, not once per event")
    func statusSinkOnChange() async throws {
        let rig = try Rig()
        rig.midi.sources = []
        rig.midi.destinations = []
        rig.coordinator.start()
        rig.midi.sources = [Rig.lc6000]
        rig.midi.destinations = [Rig.lc6000Out]
        let pipe = EventPipe()
        let seen = Seen()

        pipe.producer.tick()
        pipe.producer.devicesChanged()
        pipe.producer.tick()
        pipe.producer.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: Rig.lc6000.id)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log, onStatus: { seen.append($0) }).run(pipe.events)

        #expect(seen.values == [
            CoordinatorStatus(controllers: [ControllerStatus(deck: 1, connected: false, lastEvent: nil)]),
            CoordinatorStatus(
                controllers: [ControllerStatus(deck: 1, connected: true, lastEvent: "Connected DENON LC6000 PRIME", profile: "Custom mapping")],
                devices: [DeviceStatus(name: "DENON LC6000 PRIME", profile: "Custom mapping", note: nil)]
            ),
        ])
    }

    /// Collects what a Sendable callback is given.
    final class SeenDiagnostics: @unchecked Sendable {
        var values: [DiagnosticEvent] = []
        func append(_ event: DiagnosticEvent) { values.append(event) }
    }

    @Test("Diagnostics open and close through the pipe: events reach the window's sink only while it is open")
    func diagnosticsThroughThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        let pipe = EventPipe()
        let seen = SeenDiagnostics()

        pipe.producer.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)   // closed: not shown
        pipe.producer.diagnostics(open: true)
        pipe.producer.midi(.noteOn(channel: 0, note: 99, velocity: 127), source: Rig.lc6000.id)
        pipe.producer.diagnostics(open: false)
        pipe.producer.midi(.noteOn(channel: 0, note: 98, velocity: 127), source: Rig.lc6000.id)   // closed again
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log, onDiagnostic: { seen.append($0) }).run(pipe.events)

        #expect(seen.values.map(\.text).map { $0.hasSuffix(" UNMAPPED") } == [true])
    }

    @Test("The LED sweep starts and stops through the pipe")
    func sweepThroughThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        let pipe = EventPipe()
        let seen = SeenDiagnostics()

        pipe.producer.diagnostics(open: true)
        pipe.producer.ledSweep(delay: 0.6)
        pipe.producer.stopLEDSweep()
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log, onDiagnostic: { seen.append($0) }).run(pipe.events)

        #expect(seen.values.map(\.text) == [
            "Color sweep: velocity shown on every pad and the ring. Note what each looks like.",
            "  velocity  0 (0x00) = rgb222 r0 g0 b0",
            "LED sweep stopped.",
        ])
    }

    final class Seen: @unchecked Sendable {
        var values: [CoordinatorStatus] = []
        func append(_ status: CoordinatorStatus) { values.append(status) }
    }

    @Test("Settings changes from the pipe reach the Coordinator in order: deck, devices, LEDs")
    func settingsFromThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.coordinator.midi(.noteOn(channel: 0, note: 2, velocity: 127), source: Rig.lc6000.id)   // Cue held
        rig.osc.sent.removeAll()
        let pipe = EventPipe()

        pipe.producer.setDeck(2, controller: 0)
        pipe.producer.setDevices(input: Rig.lc6000, output: Rig.lc6000Out, controller: 0)
        pipe.producer.setLEDs(enabled: false)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent.first == OSCMessage("/Syndicate/Deck/1/Cue", [.int(0)]))
        #expect(rig.coordinator.status.controllers.map(\.deck) == [2])
        #expect(rig.midi.connected == [Rig.lc6000.id])
        #expect(rig.leds.values.allSatisfy { $0 == 0 })
    }

    @Test("A controller list from the pipe reaches the Coordinator")
    func controllersFromThePipe() async throws {
        let rig = try Rig()
        let unitB = MIDIEndpoint(id: 1005, name: "DENON LC6000 PRIME")
        rig.midi.sources.append(unitB)
        rig.coordinator.start()
        let pipe = EventPipe()

        pipe.producer.setControllers([
            ControllerSettings(deck: 1, input: nil, output: nil),
            ControllerSettings(deck: 2, input: nil, output: nil),
        ])
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.coordinator.status.controllers.map(\.deck) == [1, 2])
        #expect(rig.midi.connected == [Rig.lc6000.id, unitB.id])
    }

    @Test("An imported profile from the pipe reaches the Coordinator: Play moves to its new note")
    func setProfilesFromThePipe() async throws {
        let rig = try Rig()
        rig.coordinator.start()
        var mapping = try Mapping.bundledDefault()
        mapping.notes.buttons["play"] = 60
        let pipe = EventPipe()

        pipe.producer.setProfiles([ControllerProfile(id: "custom", name: "Custom mapping", deviceHints: ["LC6000"], mapping: mapping)])
        pipe.producer.midi(.noteOn(channel: 0, note: 60, velocity: 127), source: Rig.lc6000.id)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)

        #expect(rig.osc.sent.last == OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)]))
    }
}
