import ControllerBridgeCapture
import Foundation
import Testing

/// The standard prompt list for a DJ controller (#186): a contract shared with the draft-profile tool (#189) and the
/// web capture (#190), so its ids are pinned here.
@Suite("Capture prompts")
struct CapturePromptsTests {
    static let list = CapturePrompts.djController

    @Test("The ids, in order: idle first, deck 1's controls, Shift variants, then the deck 2 layer")
    func ids() {
        #expect(Self.list.map(\.id) == [
            "idle",
            "deck1.play", "deck1.cue", "deck1.sync",
            "deck1.hotcue1", "deck1.hotcue2", "deck1.hotcue3", "deck1.hotcue4",
            "deck1.hotcue5", "deck1.hotcue6", "deck1.hotcue7", "deck1.hotcue8",
            "deck1.pitch", "deck1.jog.touch", "deck1.jog.edge", "deck1.needle",
            "deck1.loop_in", "deck1.loop_out", "deck1.auto_loop", "deck1.browse.turn", "deck1.browse.press",
            "deck1.shift", "deck1.play.shift", "deck1.cue.shift", "deck1.hotcue1.shift",
            "layer2.select", "deck2.play",
        ])
    }

    @Test("Ids are unique, and each Shift variant repeats an earlier step")
    func shiftVariants() {
        #expect(Set(Self.list.map(\.id)).count == Self.list.count)
        for (index, prompt) in Self.list.enumerated() {
            guard let base = prompt.shiftedOf else { continue }
            #expect(Self.list[..<index].contains { $0.id == base }, "\(prompt.id) repeats \(base)")
        }
        #expect(Self.list.filter { $0.shiftedOf != nil }.map(\.id) == ["deck1.play.shift", "deck1.cue.shift", "deck1.hotcue1.shift"])
    }

    @Test("Gestures: idle first; the fader and strip move; the jog and browse knob turn; the rest press")
    func gestures() {
        let gesture = Dictionary(uniqueKeysWithValues: Self.list.map { ($0.id, $0.gesture) })
        #expect(gesture["idle"] == .idle)
        #expect(gesture["deck1.pitch"] == .move)
        #expect(gesture["deck1.needle"] == .move)
        #expect(gesture["deck1.jog.touch"] == .turn)
        #expect(gesture["deck1.jog.edge"] == .turn)
        #expect(gesture["deck1.browse.turn"] == .turn)
        #expect(Self.list.filter { $0.gesture == .press }.count == Self.list.count - 6)
    }

    @Test("The pitch prompt says which way to move, so the direction can be read from the values")
    func pitchDirection() {
        #expect(Self.list.first { $0.id == "deck1.pitch" }?.text == "Move the pitch fader slowly all the way from the top to the bottom.")
    }

    @Test("The list is the JSON file the web capture copies (#190), kept in canonical form: sorted keys, pretty, one trailing newline")
    func sharedJSON() throws {
        let json = CapturePrompts.djControllerJSON
        #expect(try JSONDecoder().decode([CapturePrompt].self, from: json) == Self.list)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var canonical = try encoder.encode(Self.list)
        canonical.append(0x0A)
        #expect(json == canonical)
    }

    @Test("The deck 2 layer steps: the select step is layer 2, and deck 2's Play repeats deck 1's on layer 2 (#217)")
    func layerSteps() {
        let select = Self.list.first { $0.id == "layer2.select" }
        let play = Self.list.first { $0.id == "deck2.play" }
        #expect(select?.layer == 2)
        #expect(select?.layerOf == nil)
        #expect(play?.layer == 2)
        #expect(play?.layerOf == "deck1.play")
        #expect(Self.list.filter { $0.layer != nil }.map(\.id) == ["layer2.select", "deck2.play"])
    }
}
