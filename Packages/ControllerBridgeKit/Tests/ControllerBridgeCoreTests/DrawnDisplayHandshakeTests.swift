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
}
