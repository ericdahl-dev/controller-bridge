import Foundation
@testable import ControllerBridgeCore
import Testing

/// A controller's color table (#197): the LC6000's rgb222, or a list of RGB-to-value entries matched by nearest RGB.
/// Expected values worked by hand (squared RGB distance).
@Suite("Color table")
struct ColorTableTests {
    static let list = ColorTable.list([
        .init(rgb: [255, 0, 0], value: 5), .init(rgb: [0, 255, 0], value: 9), .init(rgb: [0, 0, 255], value: 13),
        .init(rgb: [255, 255, 255], value: 3), .init(rgb: [0, 0, 0], value: 0),
    ])

    @Test("rgb222 is the LC6000's: red 48, orange 56, green 12, and a dim red lights red at level 1 (16)")
    func rgb222() {
        #expect([[255, 0, 0], [255, 128, 0], [0, 255, 0], [20, 0, 0], [0, 0, 0]].map { ColorTable.rgb222.velocity(for: $0) }
            == [48, 56, 12, 16, 0])
    }

    @Test("A list picks the nearest entry: (200, 30, 10) is red's 5; a tie (128, 128, 0) goes to the first entry, red")
    func nearest() {
        #expect(Self.list.velocity(for: [200, 30, 10]) == 5)
        #expect(Self.list.velocity(for: [128, 128, 0]) == 5)
        #expect(Self.list.velocity(for: [10, 240, 20]) == 9)
    }

    @Test("A list's dim fallback: (20, 0, 0) is nearest black, so it lights the nearest color instead, red; black is off")
    func dimFallback() {
        #expect(Self.list.velocity(for: [20, 0, 0]) == 5)
        #expect(Self.list.velocity(for: [0, 0, 0]) == 0)
    }

    @Test("Vivid: the LC6000's vivid velocity on rgb222; on a list, the vivid color's nearest entry (orange to red, 5)")
    func vivid() {
        #expect(ColorTable.rgb222.vivid(for: [255, 140, 0]) == vividVelocity(255, 140, 0))
        #expect(Self.list.vivid(for: [255, 140, 0]) == 5)
    }
}

/// The profile key (#197): leds.color_table is "rgb222" or a list of { "rgb": [r, g, b], "value": n }. Left out, it's
/// the LC6000's rgb222.
@Suite("Color table key")
struct ColorTableKeyTests {
    static func leds(_ json: String) throws -> Mapping.LEDs {
        try Mapping.bundledDefault(overriddenBy: Data(#"{ "leds": { \#(json) } }"#.utf8)).leds
    }

    @Test("Left out, and in the bundled LC6000, it's rgb222")
    func defaults() throws {
        #expect(try Mapping.bundledDefault().leds.colorTable == .rgb222)
        // A profile written before #197: the LED keys without color_table.
        let old = #"{ "pitch_center": 0, "ring": 0, "ring_color": [0, 0, 0], "roll_pad_color": [0, 0, 0], "loop_pad_color": [0, 0, 0], "dim_unlit_buttons": true, "beat_pulse": "off", "pulse_ms": 0, "stale_idle": "dim" }"#
        #expect(try JSONDecoder().decode(Mapping.LEDs.self, from: Data(old.utf8)).colorTable == .rgb222)
    }

    @Test("\"rgb222\" by name; a list by its entries, in order")
    func decoding() throws {
        #expect(try Self.leds(#""color_table": "rgb222""#).colorTable == .rgb222)
        let list = try Self.leds(#""color_table": [{ "rgb": [255, 0, 0], "value": 5 }, { "rgb": [0, 0, 0], "value": 0 }]"#)
        #expect(list.colorTable == .list([.init(rgb: [255, 0, 0], value: 5), .init(rgb: [0, 0, 0], value: 0)]))
    }

    @Test("Another name doesn't decode")
    func unknownName() throws {
        #expect(throws: (any Error).self) { try Self.leds(#""color_table": "rgb565""#) }
    }
}

/// The import check (#197): a color table's problems in plain words.
@Suite("Color table in the import check")
struct ColorTableImportTests {
    static func importing(_ table: String) throws -> ControllerProfile {
        try ControllerProfile.importing(Data(#"{"mapping": {"leds": {"color_table": \#(table)}}}"#.utf8),
                                        bundled: try ControllerProfile.bundled(), active: "denon-lc6000-prime")
    }

    @Test("An unknown name lists the one there is")
    func unknownName() {
        #expect(throws: MappingError.invalid(["mapping.leds.color_table: \"rgb565\" isn't one of rgb222"])) {
            try Self.importing(#""rgb565""#)
        }
    }

    @Test("Neither text nor a list says it wants either")
    func wrongKind() {
        #expect(throws: MappingError.invalid(["mapping.leds.color_table: expected text, got 7"])) {
            try Self.importing("7")
        }
    }

    @Test("An entry's color out of 0-255 or not three values, its value out of 0-127, an unknown member, an empty list")
    func entries() {
        #expect(throws: MappingError.invalid([
            "mapping.leds.color_table[0].rgb[0]: 300 is out of range, expected 0-255",
            "mapping.leds.color_table[0].value: 200 is out of range, expected 0-127",
            "mapping.leds.color_table[1].rgb: expected 3 values, got 2",
            "mapping.leds.color_table[1].name: unknown key",
        ])) {
            try Self.importing(#"[{"rgb": [300, 0, 0], "value": 200}, {"rgb": [1, 2], "value": 3, "name": "x"}]"#)
        }
        #expect(throws: MappingError.invalid(["mapping.leds.color_table: expected at least one entry"])) {
            try Self.importing("[]")
        }
    }

    @Test("A good list imports, in order")
    func good() throws {
        let profile = try Self.importing(#"[{"rgb": [255, 0, 0], "value": 5}, {"rgb": [0, 0, 255], "value": 9}]"#)
        #expect(profile.mapping.leds.colorTable == .list([.init(rgb: [255, 0, 0], value: 5), .init(rgb: [0, 0, 255], value: 9)]))
    }
}

/// The Coordinator seam (#197): a test-only profile whose pads take red 5, green 9, blue 13 and white 20 by nearest RGB.
@Suite("Color table at the Coordinator")
struct ColorTableCoordinatorTests {
    static let fourColors = #"{ "leds": { "color_table": [{ "rgb": [255, 0, 0], "value": 5 }, { "rgb": [0, 255, 0], "value": 9 }, { "rgb": [0, 0, 255], "value": 13 }, { "rgb": [255, 255, 255], "value": 20 }] } }"#

    @Test("Hot cues take the nearest entry: red 5, orange 5 (nearest red), green 9, blue 13")
    func hotCues() throws {
        let rig = try PadCountCoordinatorTests.started(Self.fourColors)
        rig.coordinator.feedback(PadCountCoordinatorTests.eightCues)
        // Slots 1, 2, 4, 6: red, orange [255, 128, 0], green, blue.
        #expect([32, 33, 35, 37].map { rig.leds[$0] } == [5, 5, 9, 13])
    }

    @Test("Loop pads in the loop color green (9); Roll pads in the roll color orange [255, 140, 0], nearest red (5)")
    func loopAndRoll() throws {
        let rig = try PadCountCoordinatorTests.started(Self.fourColors)
        rig.coordinator.feedback(PadCountCoordinatorTests.eightCues)
        PadsTests.press(rig, PadsTests.modeLoop)
        #expect(rig.leds[32] == 9)
        PadsTests.press(rig, PadsTests.modeRoll)
        #expect(rig.leds[32] == 5)
    }

    @Test("The LC6000 is unchanged: red cue 48, green cue 12")
    func lc6000() throws {
        let rig = try PadCountCoordinatorTests.started(nil)
        rig.coordinator.feedback(PadCountCoordinatorTests.eightCues)
        #expect([rig.leds[32], rig.leds[35]] == [48, 12])
    }
}
