import Foundation
@testable import ControllerBridgeCore
import Testing

/// The LC6000 jog display's upload protocol (#121, #165): Denon's SysEx frame, the 21-bit numbers, the 7-bit
/// bitstream and the byte-sum. Literals worked from the protocol notes on #121, checked against
/// tools/lc6000-display/jogbuild.py. Test data is synthetic: no other app's bytes.
@Suite("Jog display protocol")
struct JogDisplayProtocolTests {
    @Test("A frame is F0 00 02 0B 7F 10, the command, a 14-bit length, the payload, F7")
    func frame() {
        #expect(JogDisplay.frame(0x0C, JogDisplay.u21(3)) == [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x0C, 0x00, 0x03, 0x00, 0x00, 0x03, 0xF7])
        #expect(JogDisplay.frame(0x10, []) == [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x10, 0x00, 0x00, 0xF7])
    }

    @Test("A 21-bit number is three 7-bit bytes, most significant first")
    func u21() {
        #expect(JogDisplay.u21(14332) == [0x00, 0x6F, 0x7C])
        #expect(JogDisplay.u21(0x1FFFFF) == [0x7F, 0x7F, 0x7F])
    }

    @Test("The data is an MSB-first bitstream in 7-bit bytes, zero-padded: n*8/7 + 1 bytes")
    func bits7() {
        #expect(JogDisplay.bits7([0xFF]) == [0x7F, 0x40])
        #expect(JogDisplay.bits7([1, 2, 3]) == [0x00, 0x40, 0x40, 0x30])
        #expect(JogDisplay.bits7([UInt8](repeating: 0xFF, count: 7)) == [0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x7F, 0x00])
    }

    @Test("0E is the slot, then the image's 32-bit byte-sum as 8 nibbles: 6 for [1, 2, 3]; 0x3AEE x 0xFF is 0x003AB312")
    func checksum() {
        #expect(JogDisplay.checksum([1, 2, 3], slot: 1) == [0x01, 0, 0, 0, 0, 0, 0, 0, 6])
        #expect(JogDisplay.checksum([UInt8](repeating: 0xFF, count: 0x3AEE), slot: 2) == [0x02, 0x0, 0x0, 0x3, 0xA, 0xB, 0x3, 0x1, 0x2])
    }

    @Test("The hello and goodbye on the Controller port, and showing a slot on WD")
    func helloShowGoodbye() {
        #expect(JogDisplay.hello == [
            [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x60, 0x00, 0x04, 0x04, 0x01, 0x01, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x7F, 0x01, 0xF7],
        ])
        #expect(JogDisplay.goodbye == [0xF0, 0x00, 0x20, 0x7F, 0x02, 0xF7])
        #expect(JogDisplay.show(slot: 2) == [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x0A, 0x00, 0x04, 0x01, 0x00, 0x02, 0x0D, 0xF7])
    }
}
