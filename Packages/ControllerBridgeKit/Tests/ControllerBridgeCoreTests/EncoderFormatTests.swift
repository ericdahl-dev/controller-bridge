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

    @Test("A mapping without encoder_format reads two's complement, so saved profiles load as before")
    func missingKeyIsTheLC6000s() throws {
        let midi = try JSONDecoder().decode(Mapping.MIDI.self, from: Data(#"{ "input": "X", "output": "X", "channel": 1 }"#.utf8))
        #expect(midi.encoderFormat == .twosComplement)
    }

    @Test("A mapping can name another format")
    func namedFormat() throws {
        let json = #"{ "input": "X", "output": "X", "channel": 1, "encoder_format": "offset_64" }"#
        #expect(try JSONDecoder().decode(Mapping.MIDI.self, from: Data(json.utf8)).encoderFormat == .offset64)
    }

    @Test("The bundled LC6000 is two's complement, as before #193")
    func lc6000Unchanged() throws {
        #expect(try Mapping.bundledDefault().midi.encoderFormat == .twosComplement)
    }
}

/// The Coordinator seam (#193): a test-only profile whose knobs send offset 64, and the LC6000 as before. CC 6 is the
/// select turn and CC 3 the auto loop size knob, from the bundled mapping.
@Suite("Encoder format at the Coordinator")
struct EncoderFormatCoordinatorTests {
    static func rig(_ override: String?) throws -> (Coordinator, Rig.FakeOSC) {
        let mapping = try override.map { try Mapping.bundledDefault(overriddenBy: Data($0.utf8)) } ?? Mapping.bundledDefault()
        let osc = Rig.FakeOSC()
        let coordinator = Coordinator(
            mapping: mapping,
            midi: Rig.FakeMIDISystem(sources: [Rig.lc6000], destinations: [Rig.lc6000Out]),
            osc: osc, clock: Rig.FakeClock(), log: Rig.FakeLog()
        )
        coordinator.start()
        osc.sent.removeAll()
        return (coordinator, osc)
    }

    static func turn(_ coordinator: Coordinator, cc: UInt8, _ value: UInt8) {
        coordinator.midi(.controlChange(channel: 0, controller: cc, value: value), source: Rig.lc6000.id)
    }

    @Test("Offset 64: 0x42 browses down two, 0x3E up two, and 0x3F on the loop knob halves the loop")
    func offset64() throws {
        let (coordinator, osc) = try Self.rig(#"{ "midi": { "encoder_format": "offset_64" } }"#)
        Self.turn(coordinator, cc: 6, 0x42)
        Self.turn(coordinator, cc: 6, 0x3E)
        Self.turn(coordinator, cc: 3, 0x3F)
        #expect(osc.sent == [
            OSCMessage("/Syndicate/Browser/Down", [.int(1)]), OSCMessage("/Syndicate/Browser/Down", [.int(1)]),
            OSCMessage("/Syndicate/Browser/Up", [.int(1)]), OSCMessage("/Syndicate/Browser/Up", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/LoopIn", [.int(1)]),
        ])
    }

    @Test("The LC6000 is unchanged: 0x02 browses down two, 0x7F up one, and 0x01 on the loop knob doubles the loop")
    func lc6000() throws {
        let (coordinator, osc) = try Self.rig(nil)
        Self.turn(coordinator, cc: 6, 0x02)
        Self.turn(coordinator, cc: 6, 0x7F)
        Self.turn(coordinator, cc: 3, 0x01)
        #expect(osc.sent == [
            OSCMessage("/Syndicate/Browser/Down", [.int(1)]), OSCMessage("/Syndicate/Browser/Down", [.int(1)]),
            OSCMessage("/Syndicate/Browser/Up", [.int(1)]),
            OSCMessage("/Syndicate/Deck/1/LoopOut", [.int(1)]),
        ])
    }
}
