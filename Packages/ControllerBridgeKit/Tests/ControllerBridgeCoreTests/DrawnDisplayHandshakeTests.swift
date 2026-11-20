import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn display's handshake (#456): after the hello, a unit set to Custom firmware is asked whether it can draw;
/// an answer puts it in drawn mode, silence keeps today's images. Through the Coordinator, on a fake display port.
@Suite("Drawn display: handshake and fallback")
struct DrawnDisplayHandshakeTests {
    /// A fake display port that also keeps both ports' messages in one list, in order.
    final class Port: JogDisplayPort, @unchecked Sendable {
        var controller: [[UInt8]] = []
        var wd: [[UInt8]] = []
        var both: [[UInt8]] = []
        func sendController(_ bytes: [UInt8]) { controller.append(bytes); both.append(bytes) }
        func sendWD(_ bytes: [UInt8]) { wd.append(bytes); both.append(bytes) }
    }
    static let ask = DrawnDisplay.Message.capability(version: DrawnDisplay.version).bytes

    /// The LC6000 owning its display, deck 1 loaded, Settings' firmware set, then the display turned on.
    static func rig(_ firmware: DisplayFirmware) throws -> (ProfileMatchingTests.ProfileRig, Port, Rig.FakeClock) {
        let rig = ProfileMatchingTests.ProfileRig(profiles: try ControllerProfile.bundled(),
                                                  sources: [JogDisplayRingHoldTests.lc6000, JogDisplayRingHoldTests.wd])
        let port = Port(), clock = Rig.FakeClock()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: clock, log: rig.log, size: 1,
                                                          renderBeat: { _, beat in [UInt8(beat), 0, 0, 255] }) { _ in [0, 0, 0, 255] })
        rig.coordinator.start()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Loaded", [.int(1)]))
        rig.coordinator.setDisplayFirmware(firmware)
        rig.coordinator.setJogDisplay(enabled: true)
        return (rig, port, clock)
    }

    @Test("Custom: the capability question goes out on WD after the hello")
    func customAsks() throws {
        let (_, port, _) = try Self.rig(.custom)
        #expect(port.controller == JogDisplay.hello)
        #expect(port.wd.first == Self.ask)
    }

    @Test("Denon: it's never asked")
    func denonNeverAsks() throws {
        let (_, port, _) = try Self.rig(.denon)
        #expect(port.controller == JogDisplay.hello)
        #expect(!port.wd.contains(Self.ask))
    }

    /// The unit's answer: it draws, protocol 1.
    static let answer: [UInt8] = [0xF0, 0x00, 0x02, 0x0B, 0x01, 0x10, DrawnDisplay.command, 0x00, 0x02, 0x00, 0x01, 0xF7]

    /// The slot of each upload on WD: 0E's first payload byte.
    static func uploadSlots(_ port: Port) -> [UInt8] { port.wd.filter { $0.count > 9 && $0[6] == 0x0E }.map { $0[9] } }

    /// Whether `bytes` is part of an image upload (size, chunk or byte-sum).
    static func isUpload(_ bytes: [UInt8]) -> Bool { bytes.count > 6 && bytes[0] == 0xF0 && [0x0C, 0x0D, 0x0E].contains(bytes[6]) }

    /// The drawn-display messages in `port`'s WD traffic, by op byte.
    static func drawn(_ port: Port) -> [[UInt8]] { drawn(port.wd) }
    static func drawn(_ port: JogDisplayDriverTests.FakePort) -> [[UInt8]] { drawn(port.wd) }
    static func drawn(_ wd: [[UInt8]]) -> [[UInt8]] {
        wd.filter { $0.count > 9 && $0[1...5] == [0x00, 0x02, 0x0B, 0x7F, 0x10] && $0[6] == DrawnDisplay.command }
    }

    @Test("An answer with a version: drawn mode. Begin, then the deck in front (deck 1, empty), and no upload ever starts")
    func answerDraws() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        let drawn = Self.drawn(port)
        #expect(drawn.count == 11)   // the question, begin, the deck, (#464) the state, (#458) 4 texts and the tempo, (#459) the beat, (#461) the meter
        #expect(drawn.dropFirst().first == DrawnDisplay.Message.begin(version: 1).bytes)
        let deck = drawn.first { $0[9] == 0x03 }
        #expect(deck?[10] == 1 && deck?[17] == DrawnDisplay.Player.empty.rawValue)
        #expect(!port.wd.contains(where: Self.isUpload))
    }

    static let fallbackLine = "The jog display didn't answer as custom firmware that draws; it shows images"

    @Test("No reply at all, as Denon's firmware does (#466: it drops the command silently): images after half a second, exactly as today, logged once")
    func silenceFallsBack() throws {
        let (rig, port, clock) = try Self.rig(.custom)
        clock.now = 0.49
        rig.coordinator.tick()
        #expect(!port.wd.contains(where: Self.isUpload))
        clock.now = 0.5
        rig.coordinator.tick()
        #expect(Self.uploadSlots(port) == [1])
        clock.now = 9
        rig.coordinator.tick()
        #expect(rig.log.lines.filter { $0 == Self.fallbackLine }.count == 1)
        // A late answer changes nothing: images until the next connect.
        port.wd.removeAll()
        rig.coordinator.jogDisplayReply(Self.answer)
        #expect(Self.drawn(port).isEmpty)
    }

    @Test("A refusal (ack 06), which Denon's firmware never sends for this command (#466): images at once, without waiting")
    func refusalFallsBackAtOnce() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(JogDisplayDriverTests.refused)
        #expect(Self.uploadSlots(port) == [1])
        #expect(rig.log.lines.contains(Self.fallbackLine))
    }

    /// The LC6000 following its four layers, all loaded, with Custom firmware that answered: drawn mode.
    static func drawnLayers() throws -> (ProfileMatchingTests.ProfileRig, JogDisplayDriverTests.FakePort) {
        let (rig, port) = try JogDisplayRingHoldTests.owned()
        let unit = JogDisplayRingHoldTests.lc6000
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: unit, output: MIDIEndpoint(id: unit.id + 1000, name: unit.name))],
            layers: LayersTests.lc6000Layers))
        for deck in 1...4 { rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/\(deck)/Loaded", [.int(1)])) }
        rig.coordinator.setDisplayFirmware(.custom)
        rig.coordinator.setJogDisplay(enabled: true)
        rig.coordinator.jogDisplayReply(answer)
        return (rig, port)
    }

    @Test("A deck switch in drawn mode: one deck message (deck 2), no upload, and the ring is never held dark")
    func deckSwitchDraws() throws {
        let (rig, port) = try Self.drawnLayers()
        #expect(!port.wd.contains(where: Self.isUpload))
        port.wd.removeAll()
        let before = JogDisplayRingHoldTests.ring(rig).count
        rig.coordinator.midi(.noteOn(channel: 0, note: 51, velocity: 0), source: JogDisplayRingHoldTests.lc6000.id)
        rig.coordinator.midi(.noteOn(channel: 1, note: 51, velocity: 127), source: JogDisplayRingHoldTests.lc6000.id)
        let drawn = Self.drawn(port).filter { $0[9] == 0x03 }   // and its state after it (#464)
        #expect(drawn.count == 1)
        #expect(drawn.first?[9] == 0x03 && drawn.first?[10] == 2)
        #expect(!port.wd.contains(where: Self.isUpload))
        let since = JogDisplayRingHoldTests.ring(rig).dropFirst(before)
        #expect(!since.isEmpty && !since.contains(0))
    }

    static let end = DrawnDisplay.Message.end(version: 1).bytes

    @Test("Turning the jog display off in drawn mode: end, then the goodbye")
    func offSendsEnd() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        port.both.removeAll()
        rig.coordinator.setJogDisplay(enabled: false)
        #expect(port.both == [Self.end, JogDisplay.goodbye])
    }

    @Test("Stopping without quitting (the demo turning on) in drawn mode: end, then the goodbye")
    func stopSendsEnd() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        port.both.removeAll()
        rig.coordinator.stop()
        #expect(port.both.suffix(2) == [Self.end, JogDisplay.goodbye])
        #expect(port.both.filter { $0 == Self.end }.count == 1)
    }

    @Test("Quitting the app in drawn mode leaves our logo (#600): the deck again on the icon's neutral hub, then stale, no end; then the goodbye")
    func quitLeavesTheLogo() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        let deck = try #require(Self.drawn(port).last { $0[9] == 0x03 })
        let state = try #require(Self.drawn(port).last { $0[9] == 0x07 })
        port.both.removeAll()
        rig.coordinator.quit()
        var neutral = deck
        neutral[11...16] = [0x01, 0x55, 0x01, 0x55, 0x01, 0x55]   // D5D5D5: 213 is 1, 0x55 in two 7-bit bytes
        var stale = state
        stale[10] |= 0x20
        #expect(port.both == [neutral, stale, JogDisplay.goodbye])
    }

    @Test("In image mode the goodbye goes alone, as today")
    func imagesNoEnd() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(JogDisplayDriverTests.refused)
        rig.coordinator.setJogDisplay(enabled: false)
        #expect(!port.both.contains(Self.end))
        #expect(port.both.last == JogDisplay.goodbye)
    }

    @Test("The status says which display firmware was found, for Settings: Denon, Custom (images), Custom (drawn display, protocol N)")
    func firmwareFound() throws {
        let (denon, _, _) = try Self.rig(.denon)
        #expect(denon.coordinator.status.displayFound?.label == "Denon")

        let (asked, _, _) = try Self.rig(.custom)
        #expect(asked.coordinator.status.displayFound == nil)   // still asking
        asked.coordinator.jogDisplayReply(Self.answer)
        #expect(asked.coordinator.status.displayFound?.label == "Custom (drawn display, protocol 1)")
        asked.coordinator.setJogDisplay(enabled: false)
        #expect(asked.coordinator.status.displayFound == nil)   // no unit to speak of

        let (silent, _, clock) = try Self.rig(.custom)
        clock.now = 1
        silent.coordinator.tick()
        #expect(silent.coordinator.status.displayFound?.label == "Custom (images)")
    }

    @Test("Settings flipped from Denon to Custom while connected: the question goes out then, and an answer draws")
    func flipToCustomAsks() throws {
        let (rig, port, _) = try Self.rig(.denon)
        port.wd.removeAll()
        rig.coordinator.setDisplayFirmware(.custom)
        #expect(port.wd == [Self.ask])
        #expect(rig.coordinator.status.displayFound == nil)
        rig.coordinator.jogDisplayReply(Self.answer)
        #expect(rig.coordinator.status.displayFound?.label == "Custom (drawn display, protocol 1)")
    }

    @Test("Settings flipped from Custom to Denon while drawing: end, then images as on Denon's")
    func flipToDenonEnds() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        port.wd.removeAll()
        rig.coordinator.setDisplayFirmware(.denon)
        #expect(port.wd.first == Self.end)
        #expect(Self.uploadSlots(port) == [1])
        #expect(rig.coordinator.status.displayFound?.label == "Denon")
    }

    @Test("In drawn mode a new title on the deck in front sends no deck message: the deck didn't change")
    func sameDeckNoMessage() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        port.wd.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TrackInfo", [.string("Night Drive"), .string("Kid"), .string("8A"),
                                                                             .float(124), .float(200), .int(100), .int(400), .string("track")]))
        // The player type turned from empty to track: that one deck message.
        #expect(Self.drawn(port).filter { $0[9] == 0x03 }.map { $0[17] } == [DrawnDisplay.Player.track.rawValue])
        port.wd.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TrackInfo", [.string("Daybreak"), .string("Kid"), .string("8A"),
                                                                             .float(124), .float(200), .int(100), .int(400), .string("track")]))
        // Only the new title (#458), no deck message.
        #expect(Self.drawn(port) == [DrawnDisplay.Message.text(.title, "Daybreak").bytes])
    }
}

/// Settings' Firmware row (#425, #456): what the setting means, then what was found on the unit.
@Suite("Drawn display: Settings' Firmware row")
struct DisplayFirmwareHintTests {
    @Test("The row's hint says what the setting means, then what was found; nothing found, no second line")
    func hint() {
        #expect(DisplayFirmware.denon.hint(found: nil) == "Denon's own: 15 image slots, so deck 4 shows three of its four beats")
        #expect(DisplayFirmware.custom.hint(found: .customDrawn(version: 1))
                == "Custom: 16 image slots, or a drawn display if the unit's firmware answers. Only for a flashed unit\nFound: Custom (drawn display, protocol 1)")
        #expect(DisplayFirmware.custom.hint(found: .customImages).hasSuffix("\nFound: Custom (images)"))
    }
}
