import Foundation
@testable import ControllerBridgeCore
import Testing

/// #251: a whole profile file is checked against its own keys, not merged over the LC6000's; and two notes on the
/// same number collide only when they can arrive on the same channel.
@Suite("Channel-aware profile check")
struct ChannelAwareCheckTests {
    /// The bundled LC6000 as a whole profile file, with `change` applied to its mapping.
    static func profile(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var mapping = try JSONSerialization.jsonObject(with: Mapping.defaultMappingJSON()) as! [String: Any]
        change(&mapping)
        let file: [String: Any] = ["id": "test-ddj", "name": "Test DDJ", "device_hints": ["DDJ"], "mapping": mapping]
        // Sorted keys, so the file and its problem order are the same every run.
        return try JSONSerialization.data(withJSONObject: file, options: .sortedKeys)
    }

    static func problems(_ data: Data) -> [String] {
        do { _ = try ControllerProfile(decoding: data); return [] } catch let MappingError.invalid(list) { return list } catch { return ["\(error)"] }
    }

    /// A DDJ-like controller: a few buttons of its own, none of the LC6000's others.
    static func ddjNotes(_ mapping: inout [String: Any], pads: [Int] = Array(0...7)) {
        mapping["notes"] = ["play": 11, "cue": 12, "loop_in": 16, "loop_out": 17, "shift": 63, "pads": pads]
    }

    @Test("A whole profile that sets only its own buttons doesn't collide with LC6000 buttons it doesn't have")
    func ownKeysOnly() throws {
        let data = try Self.profile { mapping in
            Self.ddjNotes(&mapping)
            var pads = mapping["pads"] as! [String: Any]
            pads["channel"] = 8
            mapping["pads"] = pads
        }
        #expect(Self.problems(data) == [])
    }

    @Test("Pads on their own channel don't collide with a button of the same number; on the deck's channel they do")
    func padChannel() throws {
        let own = try Self.profile { mapping in
            Self.ddjNotes(&mapping, pads: [11, 1, 2, 3, 4, 5, 6, 7])          // pad 1 is note 11, like Play
            var pads = mapping["pads"] as! [String: Any]
            pads["channel"] = 8
            mapping["pads"] = pads
        }
        #expect(Self.problems(own) == [])
        let shared = try Self.profile { Self.ddjNotes(&$0, pads: [11, 1, 2, 3, 4, 5, 6, 7]) }
        #expect(Self.problems(shared) == ["notes.play: note 11 is also notes.pads[0]"])
    }

    @Test("Pads on a layer's pad_channel don't collide with buttons on the layer channels")
    func layerPadChannel() throws {
        let data = try Self.profile { mapping in
            Self.ddjNotes(&mapping, pads: [11, 1, 2, 3, 4, 5, 6, 7])
            var midi = mapping["midi"] as! [String: Any]
            midi["layers"] = [["channel": 1, "deck": 1, "pad_channel": 8], ["channel": 2, "deck": 2, "pad_channel": 10]]
            mapping["midi"] = midi
        }
        #expect(Self.problems(data) == [])
    }

    @Test("The LC6000 is unchanged: the bundled profile loads, and an import that reuses Back's note is still refused")
    func lc6000() throws {
        #expect(try ControllerProfile.bundled().count == 1)
        #expect(throws: MappingError.invalid(["mapping.notes.loop_in: note 16 is also notes.back"])) {
            try ControllerProfile.importing(Data(#"{"mapping": {"notes": {"loop_in": 16}}}"#.utf8),
                                            bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
        }
    }
}
