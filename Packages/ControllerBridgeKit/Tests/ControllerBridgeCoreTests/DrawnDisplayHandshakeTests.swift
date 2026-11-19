import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn display's handshake (#456): after the hello, a unit set to Custom firmware is asked whether it can draw;
/// an answer puts it in drawn mode, silence keeps today's images. Through the Coordinator, on a fake display port.
@Suite("Drawn display: handshake and fallback")
struct DrawnDisplayHandshakeTests {
    typealias Port = JogDisplayDriverTests.FakePort
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

    /// Whether `bytes` is part of an image upload (size, chunk or byte-sum).
    static func isUpload(_ bytes: [UInt8]) -> Bool { bytes.count > 6 && bytes[0] == 0xF0 && [0x0C, 0x0D, 0x0E].contains(bytes[6]) }

    /// The drawn-display messages in `port`'s WD traffic, by op byte.
    static func drawn(_ port: Port) -> [[UInt8]] {
        port.wd.filter { $0.count > 9 && $0[1...5] == [0x00, 0x02, 0x0B, 0x7F, 0x10] && $0[6] == DrawnDisplay.command }
    }

    @Test("An answer with a version: drawn mode. Begin, then the deck in front (deck 1, empty), and no upload ever starts")
    func answerDraws() throws {
        let (rig, port, _) = try Self.rig(.custom)
        rig.coordinator.jogDisplayReply(Self.answer)
        let drawn = Self.drawn(port)
        #expect(drawn.count == 3)
        #expect(drawn.dropFirst().first == DrawnDisplay.Message.begin(version: 1).bytes)
        #expect(drawn.last?[9] == 0x03 && drawn.last?[10] == 1 && drawn.last?[17] == DrawnDisplay.Player.empty.rawValue)
        #expect(!port.wd.contains(where: Self.isUpload))
    }
}
