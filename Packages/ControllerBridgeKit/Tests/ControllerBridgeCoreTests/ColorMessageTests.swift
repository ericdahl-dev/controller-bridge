import ControllerBridgeCore
import Foundation
import Testing

/// True colors with no firmware (#530, #474): Denon's top panel firmware takes a color message on the Controller port,
/// `F0 00 02 0B 7F 10 03 00 04 <note> <r> <g> <b> F7`, 7 bits a channel (#481, proven on the owner's unit). A profile
/// declares which of its LEDs take it.
@Suite("Color message")
struct ColorMessageTests {
    static func problems(_ leds: String) -> [String] { Mapping.problems(in: Data(#"{"leds": \#(leds)}"#.utf8)) }

    @Test("The LC6000's pads and ring (notes 32-40) take the color message; a profile without the key has none")
    func profileKey() throws {
        let lc6000 = try Mapping.bundledDefault()
        #expect(lc6000.leds.colorMessage?.notes == Array(32...40))
        #expect(ProfileKeys.key("leds.color_message.notes[]")?.range == 0...127)
        var leds = lc6000.leds
        leds.colorMessage = nil
        let decoded = try JSONDecoder().decode(Mapping.LEDs.self, from: JSONEncoder().encode(leds))
        #expect(decoded.colorMessage == nil)
    }

    @Test("The check takes a list of notes 0-127 and refuses anything else")
    func checkedNotes() {
        #expect(Self.problems(#"{"color_message": {"notes": [32, 40]}}"#) == [])
        #expect(Self.problems(#"{"color_message": {"notes": [128]}}"#) == [
            "leds.color_message.notes[0]: 128 is out of range, expected 0-127",
        ])
        #expect(Self.problems(#"{"color_message": {"notes": 40}}"#) == [
            "leds.color_message.notes: expected a list, got 40",
        ])
    }
}
