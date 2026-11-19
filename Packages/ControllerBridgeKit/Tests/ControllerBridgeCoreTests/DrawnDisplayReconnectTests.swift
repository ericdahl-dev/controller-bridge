import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn display recovers by itself (#464): a full state send after begin, again after a replug or reboot (the chip
/// forgets drawn mode at every boot, #466), and the stale flag while Syndicate's feedback is stopped.
@Suite("Drawn display: reconnect, reboot and stale feedback")
struct DrawnDisplayReconnectTests {
    typealias Handshake = DrawnDisplayHandshakeTests

    /// The op byte of each drawn-display message on WD, in order.
    static func ops(_ port: Handshake.Port) -> [UInt8] { Handshake.drawn(port).map { $0[9] } }

    @Test("Begin, then the full state: the deck, then the state, each once, in that order; no upload")
    func fullStateAfterBegin() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(Self.ops(port) == [0x00, 0x01, 0x03, 0x07])
        #expect(Handshake.drawn(port).last == DrawnDisplay.Message.state([]).bytes)
        #expect(!port.wd.contains(where: Handshake.isUpload))
    }
}
