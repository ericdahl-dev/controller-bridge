import ControllerBridgeCapture
import ControllerBridgeCore
import Foundation
@testable import ControllerBridgeDraft
import Testing

/// A draft is a profile file a person finishes (#310): it loads with ControllerProfile(decoding:) as written. Every
/// key decoding needs that neither the capture nor the docs gave is a placeholder from the LC6000's mapping, listed
/// in the report, never passed off as known.
@Suite("Draft decodes as a profile")
struct DraftDecodesTests {
    @Test("The LC6000 demo draft decodes, its captured values intact")
    func lc6000() throws {
        let draft = ProfileDraft.make(capture: try #require(DraftLC6000Tests.walked()))
        let profile = try ControllerProfile(decoding: Data(draft.file.text().utf8))
        #expect(profile.mapping.notes.buttons["play"] == 1)
        #expect(profile.mapping.notes.pads == Array(32...39))
    }

    @Test("A DDJ-like draft says why it doesn't load yet: the LC6000's needle placeholder (CC 64) is its browse knob")
    func ddj() throws {
        // A DDJ-400 has no needle strip, and a profile can't say so yet: the needle is required (a Core follow-up).
        let draft = ProfileDraft.make(capture: DraftCheckTests.ddj)
        #expect(draft.problems == ["needle.msb_cc: CC 64 is also browse.select_turn_cc"])
        #expect(throws: MappingError.invalid(["needle.msb_cc: CC 64 is also browse.select_turn_cc"])) {
            try ControllerProfile(decoding: Data(draft.file.text().utf8))
        }
        #expect(draft.profile.value(at: "mapping.notes.back") == nil)
    }

    @Test("Each placeholder is listed with the LC6000 value it holds, and its TODO stays")
    func placeholders() throws {
        let draft = ProfileDraft.make(capture: DraftCheckTests.ddj)
        #expect(draft.placeholders.contains { $0.key == "mapping.leds.ring" })
        #expect(draft.todos.contains { $0.key == "mapping.leds.ring" })
        #expect(!draft.placeholders.contains { $0.key.hasPrefix("mapping.notes.") })
    }
}
