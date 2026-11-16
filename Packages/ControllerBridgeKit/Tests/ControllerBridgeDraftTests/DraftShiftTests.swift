import ControllerBridgeCapture
@testable import ControllerBridgeDraft
import Testing

/// Slice 7 (#189): steps repeated with Shift held. The same note as unshifted means the app does Shift (the LC6000);
/// another note means Shift is done in hardware (#226), which is a TODO until notes.shifted lands.
@Suite("Draft Shift")
struct DraftShiftTests {
    @Test("Shifted Play sends Play's own note (the LC6000): app-side Shift, nothing to add")
    func appSide() {
        let draft = ProfileDraft.make(capture: capture(device: "X", inputs: ["X"], steps: [
            pressed("deck1.play", note: 1), pressed("deck1.play.shift", note: 1),
        ]))
        #expect(!draft.todos.contains { $0.key.hasPrefix("mapping.notes.shifted") })
    }

    @Test("Shifted Play and Cue send their own notes (a DDJ): each a TODO naming the note, for notes.shifted (#226)")
    func hardware() {
        let draft = ProfileDraft.make(capture: capture(device: "X", inputs: ["X"], steps: [
            pressed("deck1.play", note: 11), pressed("deck1.cue", note: 12),
            pressed("deck1.play.shift", note: 71), pressed("deck1.cue.shift", note: 72),
        ]))
        #expect(draft.todos.first { $0.key == "mapping.notes.shifted.play" }?.how.contains("note 71") == true)
        #expect(draft.todos.first { $0.key == "mapping.notes.shifted.cue" }?.how.contains("note 72") == true)
    }

    @Test("A shifted pad on another channel (the DDJ's channel 9) is a TODO naming the channel")
    func pad() {
        let draft = ProfileDraft.make(capture: capture(device: "X", inputs: ["X"], steps: [
            pressed("deck1.play", note: 11), pressed("deck1.hotcue1", note: 0, channel: 8), pressed("deck1.hotcue1.shift", note: 0, channel: 9),
        ]))
        #expect(draft.todos.first { $0.key == "mapping.notes.shifted.pads" }?.how.contains("channel 9") == true)
    }
}
