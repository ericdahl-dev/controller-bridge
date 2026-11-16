import Foundation
@testable import ControllerBridgeCore
import Testing

/// Relative encoder formats (#193): how a turn's CC value becomes signed ticks. Expected values worked by hand from
/// each format's definition, not from the code.
@Suite("Encoder format")
struct EncoderFormatTests {
    @Test("Two's complement (the LC6000): 0x01-0x3F forward, 0x7F is one back, 0x40 is 64 back")
    func twosComplement() {
        let format = EncoderFormat.twosComplement
        #expect([0x00, 0x01, 0x02, 0x3F, 0x7F, 0x7E, 0x40].map { format.ticks(UInt8($0)) } == [0, 1, 2, 63, -1, -2, -64])
    }

    @Test("Offset 64: 0x40 is still, 0x41 one forward, 0x3F one back")
    func offset64() {
        let format = EncoderFormat.offset64
        #expect([0x40, 0x41, 0x42, 0x7F, 0x3F, 0x3E, 0x00].map { format.ticks(UInt8($0)) } == [0, 1, 2, 63, -1, -2, -64])
    }

    @Test("Sign-magnitude: bit 6 is the sign, the low six bits the size; 0x40 is minus zero")
    func signMagnitude() {
        let format = EncoderFormat.signMagnitude
        #expect([0x00, 0x01, 0x3F, 0x41, 0x42, 0x7F, 0x40].map { format.ticks(UInt8($0)) } == [0, 1, 63, -1, -2, -63, 0])
    }
}
