import Foundation
@testable import ControllerBridgeCore
import Testing

/// Shift done in hardware (#226): notes.shifted names the note a button sends with Shift held, as the DDJ-400 and the
/// MCX8000 do. Left out or empty, the app works Shift out itself, as on the LC6000.
@Suite("Hardware Shift mapping")
struct HardwareShiftMappingTests {
    @Test("Left out it's empty; the bundled LC6000 has none; a button is named with its shifted note")
    func decoding() throws {
        let notes = try JSONDecoder().decode(Mapping.Notes.self, from: Data(#"{ "play": 1, "pads": [32] }"#.utf8))
        #expect(notes.shifted == [:])
        #expect(notes.buttons == ["play": 1])
        #expect(try Mapping.bundledDefault().notes.shifted == [:])
        let shifted = try JSONDecoder().decode(Mapping.Notes.self, from: Data(#"{ "play": 1, "pads": [32], "shifted": { "play": 4 } }"#.utf8))
        #expect(shifted.shifted == ["play": 4])
        #expect(shifted.buttons == ["play": 1])
    }
}

/// notes.shifted through save and the import check (#226).
@Suite("Hardware Shift round trip")
struct HardwareShiftRoundTripTests {
    @Test("The LC6000 encodes no shifted key, so a saved profile still reads the same")
    func noKeyWhenEmpty() throws {
        let data = try JSONEncoder().encode(Mapping.bundledDefault().notes)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["shifted"] == nil)
    }

    @Test("A profile naming shifted buttons imports, and keeps them")
    func imports() throws {
        let profile = try ControllerProfile.importing(Data(#"{"mapping": {"notes": {"shifted": {"play": 110, "beat_jump_back": 60}}}}"#.utf8),
                                                      bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
        #expect(profile.mapping.notes.shifted == ["play": 110, "beat_jump_back": 60])
    }
}

/// The Coordinator seam (#226): a test-only profile on the LC6000 rig whose Play also sends 110 with Shift held, and
/// whose Beat Jump Back sends 60 (as a DDJ-400's does), both free in the LC6000 mapping.
@Suite("Hardware Shift at the Coordinator")
struct HardwareShiftCoordinatorTests {
    static let override = #"{ "notes": { "shifted": { "play": 110, "beat_jump_back": 60, "key_lock": 111 } } }"#
    static let beatJumpBack: UInt8 = 3
    static let shiftNote: UInt8 = 26

    static func started(_ override: String?) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func press(_ rig: Rig, _ note: UInt8) -> [OSCMessage] {
        rig.osc.sent.removeAll()
        PadsTests.press(rig, note)
        return rig.osc.sent
    }

    @Test("The shifted Beat Jump Back (60) jumps a bar; its own note still jumps a beat, before and after")
    func shiftedButton() throws {
        let rig = try Self.started(Self.override)
        #expect(Self.press(rig, Self.beatJumpBack) == [OSCMessage("/Syndicate/Deck/1/SkipBeatBack", [.int(1)])])
        #expect(Self.press(rig, 60) == [OSCMessage("/Syndicate/Deck/1/SkipBarBack", [.int(1)])])
        #expect(Self.press(rig, Self.beatJumpBack) == [OSCMessage("/Syndicate/Deck/1/SkipBeatBack", [.int(1)])])
    }

    @Test("The shifted Play (110) is Play with Shift held: PlayPause")
    func shiftedPlay() throws {
        let rig = try Self.started(Self.override)
        #expect(Self.press(rig, 110) == [OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])])
    }

    @Test("The app's own Shift still works alongside: Shift held + Beat Jump Back's own note jumps a bar")
    func appShiftStillWorks() throws {
        let rig = try Self.started(Self.override)
        PadsTests.down(rig, Self.shiftNote)
        #expect(Self.press(rig, Self.beatJumpBack) == [OSCMessage("/Syndicate/Deck/1/SkipBarBack", [.int(1)])])
        #expect(Self.press(rig, 60) == [OSCMessage("/Syndicate/Deck/1/SkipBarBack", [.int(1)])])
        PadsTests.up(rig, Self.shiftNote)
        #expect(Self.press(rig, Self.beatJumpBack) == [OSCMessage("/Syndicate/Deck/1/SkipBeatBack", [.int(1)])],
                "the shifted press restored Shift to held, and releasing Shift cleared it")
    }

    @Test("A shifted press doesn't leave the Shift LED lit: after the shifted Key Lock (111), Shift (26) is back to dim")
    func shiftLEDRestored() throws {
        let rig = try Self.started(Self.override)
        PadsTests.press(rig, 111)
        #expect(rig.leds[Self.shiftNote] == 1)
    }
}

/// The LC6000 is unchanged by #226: no shifted notes, so the app's own Shift does it all.
@Suite("Hardware Shift: the LC6000 unchanged")
struct HardwareShiftLC6000Tests {
    @Test("Beat Jump Back jumps a beat, Shift + it a bar, and notes 60 and 110 do nothing")
    func lc6000() throws {
        let rig = try HardwareShiftCoordinatorTests.started(nil)
        let back = HardwareShiftCoordinatorTests.beatJumpBack
        #expect(HardwareShiftCoordinatorTests.press(rig, back) == [OSCMessage("/Syndicate/Deck/1/SkipBeatBack", [.int(1)])])
        PadsTests.down(rig, HardwareShiftCoordinatorTests.shiftNote)
        #expect(HardwareShiftCoordinatorTests.press(rig, back) == [OSCMessage("/Syndicate/Deck/1/SkipBarBack", [.int(1)])])
        PadsTests.up(rig, HardwareShiftCoordinatorTests.shiftNote)
        #expect(HardwareShiftCoordinatorTests.press(rig, 60) == [])
        #expect(HardwareShiftCoordinatorTests.press(rig, 110) == [])
    }
}
