import Foundation
@testable import ControllerBridgeCore
import Testing

/// Text and tempo in the drawn display's full state (#458): after begin, on every heartbeat and after a deck change,
/// the deck, its state, its texts (title, artist, key; the untitled words only for player "other"), then its tempo.
@Suite("Drawn display: text and tempo in the full state")
struct DrawnDisplayTextDriverTests {
    typealias Handshake = DrawnDisplayHandshakeTests
    typealias Message = DrawnDisplay.Message

    static func textAndTempo(_ port: Handshake.Port) -> [[UInt8]] {
        Handshake.drawn(port).filter { $0[9] == 0x04 || $0[9] == 0x05 }
    }

    static let daybreak = [Message.text(.title, "Daybreak").bytes, Message.text(.artist, "Bill Hamel, Jeremus").bytes,
                           Message.text(.key, "A#m").bytes, Message.tempo(128).bytes]

    @Test("After begin: deck, state, title, artist, key, tempo, then the beat")
    func afterBegin() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        port.wd.removeAll()
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(DrawnDisplayReconnectTests.ops(port) == [0x01, 0x03, 0x07, 0x04, 0x04, 0x04, 0x05, 0x08])
        #expect(Self.textAndTempo(port) == Self.daybreak)
    }

    @Test("No track: each text goes empty (clearing it) and the tempo as 0")
    func noTrack() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        port.wd.removeAll()
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(Self.textAndTempo(port) == [Message.text(.title, "").bytes, Message.text(.artist, "").bytes,
                                            Message.text(.key, "").bytes, Message.tempo(nil).bytes])
    }

    @Test("Player \"other\": the untitled words, the player type's own name, go in field 3 after the key")
    func otherPlayer() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TrackInfo", [
            .string(""), .string(""), .string(""), .float(0), .float(0), .int(0), .int(0), .string("Automation"),
        ]))
        port.wd.removeAll()
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(Self.textAndTempo(port) == [Message.text(.title, "").bytes, Message.text(.artist, "").bytes,
                                            Message.text(.key, "").bytes, Message.text(.untitled, "Automation").bytes,
                                            Message.tempo(nil).bytes])
    }

    @Test("The heartbeat carries the texts and the tempo, unchanged or not")
    func heartbeat() throws {
        let (rig, port, clock) = try Handshake.rig(.custom)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.jogDisplayReply(Handshake.answer)
        rig.coordinator.tick()   // the deck's loaded flag (#459)
        port.wd.removeAll()
        clock.now = 1.0
        rig.coordinator.tick()
        #expect(DrawnDisplayReconnectTests.ops(port) == [0x01, 0x03, 0x07, 0x04, 0x04, 0x04, 0x05, 0x08])
        #expect(Self.textAndTempo(port) == Self.daybreak)
    }

    @Test("A deck switch: deck, state, then the new deck's texts and tempo")
    func deckSwitch() throws {
        let (rig, port) = try Handshake.drawnLayers()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 2, title: "Night Drive", key: "8A", bpm: 122.5))
        port.wd.removeAll()
        rig.coordinator.midi(.noteOn(channel: 0, note: 51, velocity: 0), source: JogDisplayRingHoldTests.lc6000.id)
        rig.coordinator.midi(.noteOn(channel: 1, note: 51, velocity: 127), source: JogDisplayRingHoldTests.lc6000.id)
        #expect(Handshake.drawn(port).map { $0[9] } == [0x03, 0x07, 0x04, 0x04, 0x04, 0x05])
        #expect(Handshake.drawn(port).filter { $0[9] == 0x04 || $0[9] == 0x05 } == [Message.text(.title, "Night Drive").bytes,
                                            Message.text(.artist, "Bill Hamel, Jeremus").bytes,
                                            Message.text(.key, "8A").bytes, Message.tempo(122.5).bytes])
    }

    @Test("Same deck, a new title or tempo: only the changed message goes, once")
    func changeGoesOnce() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.jogDisplayReply(Handshake.answer)
        port.wd.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1, title: "Nightfall"))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1, title: "Nightfall"))
        #expect(Handshake.drawn(port) == [Message.text(.title, "Nightfall").bytes])
        port.wd.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1, title: "Nightfall", bpm: 130))
        #expect(Handshake.drawn(port) == [Message.tempo(130).bytes])
    }

    @Test("In image mode no text or tempo message goes")
    func notInImages() throws {
        let (rig, port, clock) = try Handshake.rig(.custom)
        clock.now = 0.5
        rig.coordinator.tick()
        port.wd.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1, title: "Nightfall"))
        #expect(Self.textAndTempo(port).isEmpty)
    }
}
