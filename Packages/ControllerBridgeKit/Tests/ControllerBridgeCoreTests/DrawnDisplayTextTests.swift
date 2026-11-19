@testable import ControllerBridgeCore
import Testing

/// The drawn display's text and tempo messages (#458), from agent3's wire spec: op 04 `<field> <escaped chars>`,
/// Windows-1252, a code 0x80-0xFF as 7F then code − 0x80, control codes dropped, a character with no cp1252 code as
/// 0x81 (the chip's box). Op 05 tempo in tenths, 14-bit.
@Suite("Drawn display: text and tempo")
struct DrawnDisplayTextTests {
    static let head: [UInt8] = [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x20]

    /// The frame for op 04 with these bytes after the field.
    static func text(_ field: UInt8, _ chars: [UInt8]) -> [UInt8] {
        let len = 2 + chars.count
        return head + [UInt8(len >> 7), UInt8(len & 0x7F), 0x04, field] + chars + [0xF7]
    }

    @Test("Plain ASCII goes as itself, after the field")
    func ascii() {
        #expect(DrawnDisplay.Message.text(.title, "Daybreak").bytes == Self.text(0, Array("Daybreak".utf8)))
        #expect(DrawnDisplay.Message.text(.key, "A#m").bytes == Self.text(2, Array("A#m".utf8)))
    }

    @Test("Empty text is the field alone: it clears that field")
    func empty() {
        #expect(DrawnDisplay.Message.text(.artist, "").bytes == Self.text(1, []))
    }

    @Test("Codes 0x80-0xFF go escaped: é 7F 69, — 7F 17, … 7F 05, € 7F 00")
    func escaped() {
        #expect(DrawnDisplay.Message.text(.artist, "Café").bytes == Self.text(1, Array("Caf".utf8) + [0x7F, 0x69]))
        #expect(DrawnDisplay.Message.text(.title, "A—B…€").bytes
                == Self.text(0, [0x41, 0x7F, 0x17, 0x42, 0x7F, 0x05, 0x7F, 0x00]))
    }

    @Test("A decomposed é (e + combining accent) is still one cp1252 code")
    func decomposed() {
        #expect(DrawnDisplay.Message.text(.title, "Cafe\u{301}").bytes == Self.text(0, Array("Caf".utf8) + [0x7F, 0x69]))
    }

    @Test("Control codes and DEL aren't text: dropped")
    func controls() {
        #expect(DrawnDisplay.Message.text(.title, "A\u{7}\tB\u{7F}\nC").bytes == Self.text(0, Array("ABC".utf8)))
    }

    @Test("A character with no cp1252 code goes as 0x81, escaped (7F 01): one box per character")
    func noGlyph() {
        #expect(DrawnDisplay.Message.text(.title, "日本").bytes == Self.text(0, [0x7F, 0x01, 0x7F, 0x01]))
        #expect(DrawnDisplay.Message.text(.title, "a🎵b").bytes == Self.text(0, [0x61, 0x7F, 0x01, 0x62]))
        // C1 controls have no glyph either; cp1252's unassigned slots must not leak through as themselves.
        #expect(DrawnDisplay.Message.text(.title, "\u{81}\u{8D}").bytes == Self.text(0, [0x7F, 0x01, 0x7F, 0x01]))
    }

    @Test("The untitled words go in field 3")
    func untitledField() {
        #expect(DrawnDisplay.Message.text(.untitled, "Automation").bytes == Self.text(3, Array("Automation".utf8)))
    }
}
