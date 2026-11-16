import LC6000Core
import Testing

/// Expected bytes are worked out by hand from the OSC 1.0 spec, never produced by the encoder.
@Suite("OSC codec")
struct OSCCodecTests {
    static func bytes(_ hex: String) -> [UInt8] {
        let digits = hex.filter { !$0.isWhitespace }
        return stride(from: 0, to: digits.count, by: 2).map {
            let start = digits.index(digits.startIndex, offsetBy: $0)
            return UInt8(digits[start...digits.index(after: start)], radix: 16)!
        }
    }

    @Test("An int32 argument: address padded to 4 bytes, ',i' tag, big-endian value")
    func int32() {
        let message = OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])
        // "/Syndicate/Deck/1/PlayPause" is 27 bytes, + 1 NUL = 28.
        let expected = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f506c 61795061 75736500
            2c690000
            00000001
            """)
        #expect(message.encoded() == expected)
    }

    @Test("A float32 argument: ',f' tag, IEEE 754 big-endian")
    func float32() {
        let message = OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(-0.25)])
        // 29 address bytes + 1 NUL, padded to 32. -0.25 is 0xBE800000.
        let expected = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f5465 6d706f53 6c696465 72000000
            2c660000
            be800000
            """)
        #expect(message.encoded() == expected)
    }

    @Test("A string whose length is a multiple of 4 still gets a NUL, then pads to 4 NULs")
    func stringPadding() {
        let message = OSCMessage("/abc", [.string("deck"), .string("x")])
        let expected = Self.bytes("""
            2f616263 00000000
            2c737300
            6465636b 00000000
            78000000
            """)
        #expect(message.encoded() == expected)
    }

    @Test("Multi-argument route: HotCue 3 1 carries two int32s under ',ii'")
    func hotCuePress() {
        let message = OSCMessage("/Syndicate/Deck/1/HotCue", [.int(3), .int(1)])
        // 24 address bytes + 1 NUL, padded to 28.
        let expected = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f486f 74437565 00000000
            2c696900
            00000003 00000001
            """)
        #expect(message.encoded() == expected)
    }

    @Test("SetCueLoop 2: a 28-byte address gets 4 NULs")
    func setCueLoop() {
        let message = OSCMessage("/Syndicate/Deck/1/SetCueLoop", [.int(2)])
        let expected = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f5365 74437565 4c6f6f70 00000000
            2c690000
            00000002
            """)
        #expect(message.encoded() == expected)
    }

    @Test("Decodes a feedback message with strings, floats and ints (TrackInfo s s s f f i i s)")
    func decodeTrackInfo() throws {
        let packet = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f5472 61636b49 6e666f00
            2c737373 66666969 73000000
            536f6e67 00000000
            42616e64 00000000
            4d697800
            43000000
            43758000
            00000008
            00000001
            416d0000
            """)
        #expect(try OSCPacket(decoding: packet).messages == [
            OSCMessage("/Syndicate/Deck/1/TrackInfo", [
                .string("Song"), .string("Band"), .string("Mix"),
                .float(128), .float(245.5), .int(8), .int(1), .string("Am"),
            ]),
        ])
    }
}
