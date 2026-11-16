import Foundation
@testable import ControllerBridgeCore
import Testing

/// The jog display at the Coordinator seam (#165): the display shows the deck in front, in its deck color, on connect,
/// on a layer change and on a deck-color change, and says goodbye when the unit goes. Syndicate's factory deck colors
/// (#123): deck 1 red, deck 2 yellow.
@Suite("Jog display at the Coordinator")
struct JogDisplayCoordinatorTests {
    typealias Port = JogDisplayDriverTests.FakePort

    /// What each upload showed, read back from the fake renderer's calls.
    final class Shown: @unchecked Sendable { var contents: [JogDisplayContent] = [] }

    static func attach(_ rig: Rig) -> (Port, Shown) {
        let port = Port(), shown = Shown()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1) { content in
            shown.contents.append(content)
            return [UInt8(content.deck), 0, 0, 255]
        })
        rig.coordinator.setJogDisplay(enabled: true)
        return (port, shown)
    }

    @Test("Off by default: attached, through a start, a layer change, a load, playing and ticks, nothing goes to either port")
    func offByDefault() throws {
        let rig = try Rig()
        let port = Port()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1) { _ in [0, 0, 0, 255] })
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers
        ))
        LayersTests.switchLayer(rig, from: 1, to: 2)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 2))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(1)]))
        for step in 1...20 { rig.clock.now = Double(step) * 0.05; rig.coordinator.tick() }
        #expect(port.controller == [])
        #expect(port.wd == [])
    }

    @Test("Turned off while showing: goodbye, then nothing more; on again: hello")
    func turnOff() throws {
        let rig = try Rig()
        let (port, _) = Self.attach(rig)
        rig.coordinator.start()
        port.controller.removeAll()
        rig.coordinator.setJogDisplay(enabled: false)
        #expect(port.controller == [JogDisplay.goodbye])
        port.wd.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)]))
        rig.clock.now = 1
        rig.coordinator.tick()
        #expect(port.wd == [])
        rig.coordinator.setJogDisplay(enabled: true)
        #expect(port.controller == [JogDisplay.goodbye] + JogDisplay.hello)
    }

    /// Answers the upload in flight: every ack, then the commit.
    static func answer(_ rig: Rig, _ port: Port) {
        let acks = port.wd.filter { $0.count > 6 && [0x0C, 0x0D, 0x0E].contains($0[6]) }.count
        for _ in 0..<acks { rig.coordinator.jogDisplayReply(JogDisplayDriverTests.accepted) }
        rig.coordinator.jogDisplayReply(JogDisplayDriverTests.committed)
        port.wd.removeAll()
    }

    @Test("Connect says hello and shows deck 1 in red")
    func connect() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        #expect(port.controller == JogDisplay.hello)
        #expect(shown.contents == [JogDisplayContent(deck: 1, color: [255, 0, 0])])
    }

    @Test("Switching to layer 2 shows deck 2 in yellow, once the first image is up")
    func layerChange() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers
        ))
        LayersTests.switchLayer(rig, from: 1, to: 2)
        Self.answer(rig, port)
        #expect(shown.contents.last == JogDisplayContent(deck: 2, color: [255, 255, 0]))
    }

    @Test("Syndicate changing deck 1's color redraws it")
    func colorChange() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        Self.answer(rig, port)
        // Cue palette slot 1, deck 1's color (#123), now blue.
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(0), .int(0), .int(255)]))
        #expect(shown.contents.last == JogDisplayContent(deck: 1, color: [0, 0, 255]))
    }

    @Test("Stop says goodbye")
    func stop() throws {
        let rig = try Rig()
        let (port, _) = Self.attach(rig)
        rig.coordinator.start()
        port.controller.removeAll()
        rig.coordinator.stop()
        #expect(port.controller == [JogDisplay.goodbye])
    }

    @Test("Unplugging the unit says goodbye; plugging it back says hello again")
    func unplug() throws {
        let rig = try Rig()
        let (port, _) = Self.attach(rig)
        rig.coordinator.start()
        port.controller.removeAll()
        rig.midi.sources.removeAll { $0.id == Rig.lc6000.id }
        rig.coordinator.devicesChanged()
        #expect(port.controller == [JogDisplay.goodbye])
        rig.midi.sources.append(Rig.lc6000)
        rig.coordinator.devicesChanged()
        #expect(port.controller == [JogDisplay.goodbye] + JogDisplay.hello)
    }
}

/// The marker and the play light on the WD port (#165), at the Coordinator seam. Pitch bend on ch1 is E0 lsb msb;
/// the play light is note 1 on ch1. Worked by hand at 120 BPM: a quarter-second into beat 1 is 2048 (E0 00 10).
@Suite("Jog marker at the Coordinator")
struct JogMarkerCoordinatorTests {
    static func started() throws -> (Rig, JogDisplayDriverTests.FakePort) {
        let rig = try Rig()
        let (port, _) = JogDisplayCoordinatorTests.attach(rig)
        rig.coordinator.start()
        JogDisplayCoordinatorTests.answer(rig, port)
        port.wd.removeAll()
        return (rig, port)
    }

    static func bends(_ port: JogDisplayDriverTests.FakePort) -> [[UInt8]] { port.wd.filter { $0.first == 0xE0 } }
    static func lights(_ port: JogDisplayDriverTests.FakePort) -> [[UInt8]] { port.wd.filter { $0.count == 3 && $0[0] == 0x90 && $0[1] == 1 } }

    static func feed(_ rig: Rig, _ path: String, _ argument: OSCArgument) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/" + path, [argument]))
    }

    static func tick(_ rig: Rig, at time: Double) {
        rig.clock.now = time
        rig.coordinator.tick()
    }

    @Test("Playing, the hand follows the master clock: 0 on beat 1, 2048 a quarter-second on")
    func clockHand() throws {
        let (rig, port) = try Self.started()
        Self.feed(rig, "Deck/1/Playing", .int(1))
        Self.feed(rig, "Header/BPM", .float(120))
        Self.feed(rig, "Header/Clock", .int(1))
        Self.tick(rig, at: 0)
        Self.tick(rig, at: 0.25)
        #expect(Self.bends(port) == [[0xE0, 0x00, 0x00], [0xE0, 0x00, 0x10]])
    }

    @Test("At most 30 a second: ticks every 10 ms send at 0, 0.04 and 0.08 s (0, 327, 655)")
    func rateLimit() throws {
        let (rig, port) = try Self.started()
        Self.feed(rig, "Deck/1/Playing", .int(1))
        Self.feed(rig, "Header/BPM", .float(120))
        Self.feed(rig, "Header/Clock", .int(1))
        for step in 0...9 { Self.tick(rig, at: Double(step) * 0.01) }
        #expect(Self.bends(port) == [[0xE0, 0x00, 0x00], [0xE0, 0x47, 0x02], [0xE0, 0x0F, 0x05]])
    }

    @Test("Paused, the clock doesn't move it; a quarter turn of the platter (900 counts) does: 4096")
    func pausedPlatter() throws {
        let (rig, port) = try Self.started()
        Self.feed(rig, "Header/BPM", .float(120))
        Self.feed(rig, "Header/Clock", .int(2))
        Self.tick(rig, at: 0.2)
        #expect(Self.bends(port) == [])
        // Platter at 1000, then 1900: 900 counts forward (CC 17 then CC 49).
        for (msb, lsb) in [(UInt8(7), UInt8(104)), (14, 108)] {
            rig.coordinator.midi(.controlChange(channel: 0, controller: 17, value: msb), source: Rig.lc6000.id)
            rig.coordinator.midi(.controlChange(channel: 0, controller: 49, value: lsb), source: Rig.lc6000.id)
        }
        Self.tick(rig, at: 0.3)
        #expect(Self.bends(port) == [[0xE0, 0x00, 0x20]])
    }

    @Test("The play light: 127 while playing; loaded and paused, it blinks every half-second")
    func playLight() throws {
        let (rig, port) = try Self.started()
        Self.feed(rig, "Deck/1/Loaded", .int(1))
        Self.feed(rig, "Deck/1/Playing", .int(1))
        Self.tick(rig, at: 0.1)
        #expect(Self.lights(port) == [[0x90, 0x01, 0x7F]])
        Self.feed(rig, "Deck/1/Playing", .int(0))
        Self.tick(rig, at: 0.2)
        Self.tick(rig, at: 0.5)
        Self.tick(rig, at: 1.0)
        #expect(Self.lights(port) == [[0x90, 0x01, 0x7F], [0x90, 0x01, 0x00], [0x90, 0x01, 0x7F]])
    }
}

/// What the display shows comes from Syndicate's TrackInfo (#165): title, artist, key, BPM and player type, from the
/// real capture's argument order <title> <artist> <key> <bpm> <length> <bars> <beats> <player_type>. Redrawn only when
/// it changes.
@Suite("Jog display content")
struct JogDisplayContentTests {
    static func trackInfo(deck: Int = 1, title: String = "Daybreak", key: String = "A#m", bpm: Float = 128) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/\(deck)/TrackInfo", [
            .string(title), .string("Bill Hamel, Jeremus"), .string(key), .float(bpm), .float(428.5), .int(229), .int(914), .string("track"),
        ])
    }

    static let daybreak = JogDisplayContent(deck: 1, color: [255, 0, 0], title: "Daybreak", artist: "Bill Hamel, Jeremus",
                                            key: "A#m", bpm: 128, playerType: "track")

    @Test("A loaded track's TrackInfo shows its title, artist, key, BPM and player type")
    func trackInfo() throws {
        let rig = try Rig()
        let (port, shown) = JogDisplayCoordinatorTests.attach(rig)
        rig.coordinator.start()
        JogDisplayCoordinatorTests.answer(rig, port)
        rig.coordinator.feedback(Self.trackInfo())
        #expect(shown.contents.last == Self.daybreak)
    }

    @Test("The same TrackInfo again draws nothing new; a key change redraws")
    func onlyOnChange() throws {
        let rig = try Rig()
        let (port, shown) = JogDisplayCoordinatorTests.attach(rig)
        rig.coordinator.start()
        JogDisplayCoordinatorTests.answer(rig, port)
        rig.coordinator.feedback(Self.trackInfo())
        JogDisplayCoordinatorTests.answer(rig, port)
        let drawn = shown.contents.count
        rig.coordinator.feedback(Self.trackInfo())
        rig.coordinator.tick()
        #expect(shown.contents.count == drawn)
        rig.coordinator.feedback(Self.trackInfo(key: "Bm"))
        #expect(shown.contents.last?.key == "Bm")
    }

    @Test("Another deck's TrackInfo doesn't change what deck 1's display shows")
    func otherDeck() throws {
        let rig = try Rig()
        let (port, shown) = JogDisplayCoordinatorTests.attach(rig)
        rig.coordinator.start()
        JogDisplayCoordinatorTests.answer(rig, port)
        rig.coordinator.feedback(Self.trackInfo(deck: 2))
        #expect(shown.contents == [JogDisplayContent(deck: 1, color: [255, 0, 0])])
    }
}

/// The jog display's switch and the unit's answers come through the pipe, in order with everything else (#165).
@Suite("Jog display through the pipe")
struct JogDisplayPipeTests {
    @Test("setJogDisplay(enabled: true) from the pipe says hello; a reply from the pipe reaches the driver")
    func throughThePipe() async throws {
        let rig = try Rig()
        let port = JogDisplayDriverTests.FakePort()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1) { _ in [0, 0, 0, 255] })
        rig.coordinator.start()
        let pipe = EventPipe()
        pipe.producer.setJogDisplay(enabled: true)
        pipe.producer.jogDisplayReply(JogDisplayDriverTests.refused)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)
        #expect(port.controller == JogDisplay.hello)
        #expect(rig.log.lines.contains("The jog display refused the image (ack 06); it keeps what it showed"))
    }
}
