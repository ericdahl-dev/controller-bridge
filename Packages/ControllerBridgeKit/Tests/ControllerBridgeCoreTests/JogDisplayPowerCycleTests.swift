import Foundation
@testable import ControllerBridgeCore
import Testing

/// After a power cycle (#606): the top panel may miss the hello, so it's sent again until it answers; and the display
/// chip's own boot sequence covers the host's images until it says ready (its first 10 reply), so the show then goes
/// again. Only messages the app already sends, newly timed.
@Suite("Jog display after a power cycle")
struct JogDisplayPowerCycleTests {
    typealias DriverRig = JogDisplayDriverTests.DriverRig

    /// Ticks the driver every 0.1 s up to `until`, noting when each hello pair went out.
    static func run(_ rig: DriverRig, from start: Double = 0, until end: Double) -> [Double] {
        var times: [Double] = []
        var t = start
        while t <= end + 1e-9 {
            rig.clock.now = t
            let before = rig.port.controller.count
            rig.driver.tick()
            if rig.port.controller.count > before {
                #expect(Array(rig.port.controller.dropFirst(before)) == JogDisplay.hello)
                times.append((t * 10).rounded() / 10)
            }
            t += 0.1
        }
        return times
    }

    @Test("No answer to the hello: the same hello pair again at 1, 3, 7, 15 and 31 s, then never")
    func helloAgain() {
        let rig = DriverRig()
        rig.driver.connect()
        #expect(Self.run(rig, until: 120) == [1, 3, 7, 15, 31])
    }

    @Test("The top panel answers (after the 1 s hello): no more; a goodbye stops them too, and a reconnect starts over")
    func answerStops() {
        let rig = DriverRig()
        rig.driver.connect()
        #expect(Self.run(rig, until: 2) == [1])
        rig.driver.helloAnswered()
        #expect(Self.run(rig, from: 2.1, until: 60).isEmpty)

        let other = DriverRig()
        other.driver.connect()
        _ = Self.run(other, until: 2)
        other.driver.disconnect()
        #expect(Self.run(other, from: 2.1, until: 60).isEmpty)
        other.port.controller.removeAll()
        other.driver.connect()
        #expect(Self.run(other, from: 60, until: 120) == [61, 63, 67, 75, 91])
    }

    final class Lines: @unchecked Sendable { var list: [String] = [] }

    static func traced(_ rig: DriverRig) -> Lines {
        let lines = Lines()
        rig.driver.trace = { _, text in if !text.hasPrefix("CTL out") && !text.hasPrefix("WD") && !text.hasPrefix("event") { lines.list.append(text) } }
        return lines
    }

    @Test("The trace says when the hello wasn't answered, each re-send, and what stopped them")
    func helloTrace() {
        let rig = DriverRig()
        let lines = Self.traced(rig)
        rig.driver.connect()
        _ = Self.run(rig, until: 3.5)
        rig.driver.helloAnswered()
        rig.driver.helloAnswered()
        #expect(lines.list == [
            "jog display: no answer to the hello in 0.5 s: sending it again at 1, 3, 7, 15, 31 s",
            "jog display: hello again (1 of 5)",
            "jog display: hello again (2 of 5)",
            "jog display: the top panel answered the hello 3.5 s after it: no more re-sends",
        ])

        let gone = DriverRig()
        let goneLines = Self.traced(gone)
        gone.driver.connect()
        _ = Self.run(gone, until: 1.5)
        gone.driver.disconnect()
        #expect(goneLines.list.last == "jog display: hello re-sends stop: goodbye")

        let silent = DriverRig()
        let silentLines = Self.traced(silent)
        silent.driver.connect()
        _ = Self.run(silent, until: 120)
        #expect(silentLines.list.suffix(2) == [
            "jog display: hello again (5 of 5)",
            "jog display: the top panel never answered the hello (5 re-sends, 31.5 s): no more",
        ])
        #expect(silent.log.lines.filter { $0.contains("never answered the hello") }.count == 1)
    }

    @Test("Answered in time: no trace line about the hello at all")
    func answeredInTime() {
        let rig = DriverRig()
        let lines = Self.traced(rig)
        rig.driver.connect()
        rig.clock.now = 0.02
        rig.driver.helloAnswered()
        _ = Self.run(rig, from: 0.1, until: 60)
        #expect(lines.list.isEmpty)
    }

    // MARK: Through the Coordinator: the answer is the top panel's ch16 note 55 on, on the display owner's port.

    typealias Port = JogDisplayDriverTests.FakePort
    typealias CoordinatorRig = ProfileMatchingTests.ProfileRig

    /// The LC6000 owning the display, its driver on a clock the test moves; the display on.
    static func owned() throws -> (CoordinatorRig, Port, Rig.FakeClock) {
        let rig = ProfileMatchingTests.ProfileRig(profiles: try ControllerProfile.bundled(),
                                                  sources: [JogDisplayRingHoldTests.lc6000, JogDisplayRingHoldTests.wd])
        let port = Port(), clock = Rig.FakeClock()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: clock, log: rig.log, size: 1,
                                                          renderBeat: { _, beat in [UInt8(beat), 0, 0, 255] }) { _ in [0, 0, 0, 255] })
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.setJogDisplay(enabled: true)
        return (rig, port, clock)
    }

    /// Hello pairs sent from `start` to `end`, ticking the Coordinator every 0.1 s.
    static func hellos(_ rig: CoordinatorRig, _ port: Port, _ clock: Rig.FakeClock, from start: Double, until end: Double) -> Int {
        port.controller.removeAll()
        var t = start
        while t <= end + 1e-9 {
            clock.now = t
            rig.clock.now = t
            rig.coordinator.tick()
            t += 0.1
        }
        return port.controller.filter { $0 == JogDisplay.hello[1] }.count
    }

    @Test("The LC6000's ch16 note 55 on at 127 stops the re-sends; on another channel, at 0, or from another port it doesn't")
    func answerThroughCoordinator() throws {
        let lc6000 = JogDisplayRingHoldTests.lc6000.id, iac = MIDIEndpoint.ID(1000)
        for (event, source, stops) in [(MIDIEvent.noteOn(channel: 15, note: 55, velocity: 127), lc6000, true),
                                       (.noteOn(channel: 0, note: 55, velocity: 127), lc6000, false),
                                       (.noteOn(channel: 15, note: 55, velocity: 0), lc6000, false),
                                       (.noteOn(channel: 15, note: 55, velocity: 127), iac, false)] {
            let (rig, port, clock) = try Self.owned()
            #expect(port.controller.contains(JogDisplay.hello[1]))
            clock.now = 0.2
            rig.coordinator.midi(event, source: source)
            #expect(Self.hellos(rig, port, clock, from: 0.3, until: 40) == (stops ? 0 : 5), "\(event) from \(source)")
        }
    }

    // MARK: A: the display chip's first 10 reply since the hello is "ready": the show goes again.

    static let ready = JogDisplayDriverTests.committed

    /// Connected, deck 1 uploaded into slot 1 with every ack, stored by the commit grace (no 10 reply: the chip is still
    /// booting) and shown; WD's record cleared.
    static func shownByGrace(_ rig: DriverRig) -> JogDisplay.Upload {
        rig.driver.connect()
        rig.driver.helloAnswered()
        rig.driver.show(JogDisplayContent(deck: 1, color: [255, 0, 0]))
        let upload = JogDisplayDriverTests.upload(deck: 1, slot: 1)
        for _ in 0..<upload.expectedAcks { rig.driver.reply(JogDisplayDriverTests.accepted) }
        rig.clock.now = 0.4
        rig.driver.tick()
        #expect(rig.port.wd.last == upload.show)
        rig.port.wd.removeAll()
        return upload
    }

    @Test("Ready with nothing in flight: the last show once more, at once; a second 10 reply sends nothing")
    func readyShowsAgain() {
        let rig = DriverRig()
        let lines = Self.traced(rig)
        let upload = Self.shownByGrace(rig)
        rig.clock.now = 22
        rig.driver.reply(Self.ready)
        #expect(rig.port.wd == [upload.show])
        rig.driver.reply(Self.ready)
        rig.driver.tick()
        #expect(rig.port.wd == [upload.show])
        #expect(lines.list == ["jog display: the display said ready (its first 10 reply since the hello): show slot 1 sent again"])
    }
}
