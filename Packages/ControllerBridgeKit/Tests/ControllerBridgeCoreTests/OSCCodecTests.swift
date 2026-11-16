import ControllerBridgeCore
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

    @Test("A negative int32 is two's complement, big-endian: BeatSkip -1 carries ffffffff")
    func negativeInt32() {
        let message = OSCMessage("/Syndicate/Deck/1/BeatSkip", [.int(-1)])
        // "/Syndicate/Deck/1/BeatSkip" is 26 bytes, + 1 NUL, padded to 28.
        let expected = Self.bytes("""
            2f53796e 64696361 74652f44 65636b2f 312f4265 6174536b 69700000
            2c690000
            ffffffff
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

    @Test("Skips unsupported OSC 1.0 tags by their size: h (8), T (none), b (sized blob), d (8)")
    func skipsSizedTags() throws {
        let packet = Self.bytes("""
            2f610000
            2c685462 64690000
            00000000 0000002a
            00000003 01020300
            3ff00000 00000000
            00000007
            """)
        #expect(try OSCPacket(decoding: packet).messages == [OSCMessage("/a", [.int(7)])])
    }

    // Syndicate sends some feedback as OSC 1.1 arrays: the guide's "[i slot, i R, i G, i B]". Brackets carry no data;
    // the arguments inside are read in order, flattened (live bug: ColorPalette arrived with no arguments).

    @Test("An OSC array is flattened: ColorPalette ',[iiii]' 1, 255, 0, 0 decodes to four ints")
    func decodesArray() throws {
        let packet = Self.bytes("""
            2f53796e 64696361 74652f43 6f6c6f72 50616c65 74746500
            2c5b6969 69695d00
            00000001 000000ff 00000000 00000000
            """)
        #expect(try OSCPacket(decoding: packet).messages == [
            OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(255), .int(0), .int(0)]),
        ])
    }

    @Test("Arrays of mixed arguments, one after another, flatten in order: ',[is][is]' 3, \"Drop\", 0, \"\"")
    func decodesArraysInSequence() throws {
        let packet = Self.bytes("""
            2f610000
            2c5b6973 5d5b6973 5d000000
            00000003 44726f70 00000000
            00000000 00000000
            """)
        #expect(try OSCPacket(decoding: packet).messages == [OSCMessage("/a", [.int(3), .string("Drop"), .int(0), .string("")])])
    }

    @Test("An unknown tag ends the arguments: the ones before it are kept")
    func stopsAtUnknownTag() throws {
        let packet = Self.bytes("""
            2f610000
            2c695869 00000000
            00000001 00000002
            """)
        #expect(try OSCPacket(decoding: packet).messages == [OSCMessage("/a", [.int(1)])])
    }

    @Test("A bundle with a message and a nested bundle decodes to both messages in order")
    func bundle() throws {
        let packet = Self.bytes("""
            2362756e 646c6500 00000000 00000001
            0000000c
              2f610000 2c690000 00000001
            00000020
              2362756e 646c6500 00000000 00000001
              0000000c
                2f620000 2c690000 00000002
            """)
        #expect(try OSCPacket(decoding: packet).messages == [
            OSCMessage("/a", [.int(1)]),
            OSCMessage("/b", [.int(2)]),
        ])
    }

    @Test("A bundle element that claims more bytes than remain is refused")
    func bundleElementTooLong() {
        let packet = Self.bytes("""
            2362756e 646c6500 00000000 00000001
            ffffffff
            2f610000 2c690000 00000001
            """)
        #expect(throws: OSCError.truncated) { try OSCPacket(decoding: packet) }
    }

    @Test("Bundles nested deeper than 8 are refused, so a hostile packet can't recurse without bound")
    func bundleDepthLimit() throws {
        // Wraps an element in a bundle header (immediate time tag) and its size prefix.
        func wrap(_ element: [UInt8]) -> [UInt8] {
            Self.bytes("2362756e 646c6500 00000000 00000001") + [0, 0, 0, UInt8(element.count)] + element
        }
        let message = Self.bytes("2f610000 2c690000 00000001")
        let eight = (0..<8).reduce(message) { inner, _ in wrap(inner) }
        #expect(try OSCPacket(decoding: eight).messages == [OSCMessage("/a", [.int(1)])])
        #expect(throws: OSCError.malformed("bundles nested too deep")) { try OSCPacket(decoding: wrap(eight)) }
    }
}
