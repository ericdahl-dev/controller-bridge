@testable import ControllerBridgeCore
import Testing

/// The drawn display's time message (#460), as agent3 and agent1 agreed: op 06 `eh el lh ll`, len 5, elapsed and the
/// track's length in whole seconds, 14-bit hi/lo, clamped to 16383; length 0 is unknown (elapsed only, no arc).
@Suite("Drawn display: time")
struct DrawnDisplayTimeTests {
    static func time(_ elapsed: Int, _ length: Int) -> [UInt8] {
        [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x20, 0x00, 0x05, 0x06,
         UInt8(elapsed >> 7), UInt8(elapsed & 0x7F), UInt8(length >> 7), UInt8(length & 0x7F), 0xF7]
    }

    @Test("Elapsed and length in whole seconds, down to the second shown: 83.9 s of 428.5 s is 83 of 428")
    func seconds() {
        #expect(DrawnDisplay.Message.time(elapsed: 83.9, length: 428.5).bytes == Self.time(83, 428))
        #expect(DrawnDisplay.Message.time(elapsed: 0, length: 200).bytes == Self.time(0, 200))
    }

    @Test("Unknown, NaN or no length is 0; unknown or negative elapsed is 0")
    func unknown() {
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: nil).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: .nan).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: 0).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: nil, length: 200).bytes == Self.time(0, 200))
        #expect(DrawnDisplay.Message.time(elapsed: -3, length: 200).bytes == Self.time(0, 200))
    }

    @Test("Both clamp to 16383 (4:33:03)")
    func clamp() {
        #expect(DrawnDisplay.Message.time(elapsed: 20000, length: .infinity).bytes == Self.time(16383, 16383))
    }

    @Test("Elapsed past the end (Syndicate's position can run a hair over) stays as sent; the chip shows 0 remaining")
    func pastTheEnd() {
        #expect(DrawnDisplay.Message.time(elapsed: 201.2, length: 200).bytes == Self.time(201, 200))
    }
}
