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

/// The draft's check runs the decoder too (#310): shape rules it throws (such as a cycling pad mode with no cycle
/// button) show in the report like the import check's problems.
@Suite("Draft check includes the decoder's rules")
struct DraftShapeProblemTests {
    @Test("Docs say the pad mode cycles, but there's no mode_cycle button: the decoder's words")
    func cycle() throws {
        let docs = try DocsFacts(json: Data(#"{ "mapping": { "pads": { "mode_select": "cycle" } } }"#.utf8))
        let draft = ProfileDraft.make(capture: try #require(DraftLC6000Tests.walked()), docs: docs)
        #expect(draft.problems == ["pads: mode_select is cycle, but notes has no mode_cycle button"])
    }
}
