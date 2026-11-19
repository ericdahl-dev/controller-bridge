@testable import ControllerBridgeCore
import Testing

/// A deck's drawn state as the renderer's drawnImage takes it (#465): its content and its live values.
@Suite("Drawn display: the preview's image inputs")
struct DrawnPreviewImageTests {
    typealias Message = DrawnDisplay.Message

    static func state(_ messages: [Message]) -> DrawnDisplayState {
        var state = DrawnDisplayState()
        state.apply(Message.begin(version: 1).bytes)
        for message in messages { state.apply(message.bytes) }
        return state
    }

    @Test("A track: its deck, color, title, artist, key, tempo and player type, as the content")
    func track() throws {
        let state = Self.state([.deck(number: 2, color: [255, 0, 0], player: .track), .state([.loaded, .playing]),
                                .text(.title, "Café del Mar"), .text(.artist, "Energy 52"), .text(.key, "8A"),
                                .text(.untitled, ""), .tempo(tenths: 1245)])
        let content = try #require(state.preview(now: 0, timeAt: nil)).content
        #expect(content == JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Café del Mar", artist: "Energy 52",
                                             key: "8A", bpm: 124.5, playerType: "track"))
    }

    @Test("No title: the untitled words as the player type, so the renderer says them; no tempo is nil")
    func untitled() throws {
        let midi = Self.state([.deck(number: 1, color: [0, 0, 255], player: .midiClip), .text(.title, ""),
                               .text(.untitled, "Midi clip"), .tempo(tenths: 0)])
        let content = try #require(midi.preview(now: 0, timeAt: nil)).content
        #expect(content.title == nil && content.bpm == nil && content.artist == nil && content.key == nil)
        #expect(JogDisplayWords.untitled(content.playerType).title == "Midi clip")
        let empty = Self.state([.deck(number: 1, color: [0, 0, 255], player: .empty), .text(.title, ""),
                                .text(.untitled, "No track")])
        #expect(try #require(empty.preview(now: 0, timeAt: nil)).content.playerType == "empty")
    }

    @Test("Stale feedback is the content's waiting look")
    func stale() throws {
        let state = Self.state([.deck(number: 1, color: [0, 0, 255], player: .track), .state([.loaded, .stale])])
        #expect(try #require(state.preview(now: 0, timeAt: nil)).content.stale)
    }

    @Test("The live values: beat, needle, meter, phase and time; no beat, and an unknown phase, are nil")
    func live() throws {
        let state = Self.state([.deck(number: 1, color: [0, 0, 255], player: .track), .beat(3), .needle(4096),
                                .meter(level: 64, peak: 90), .phase(-164), .time(elapsedSeconds: 65, lengthSeconds: 293)])
        let live = try #require(state.preview(now: 0, timeAt: 0)).live
        #expect(live == DrawnLive(beat: 3, needle: 4096, meter: .init(level: 64, peak: 90), phase: -164,
                                  time: .init(elapsed: 65, length: 293), look: .normal))
        let quiet = Self.state([.deck(number: 1, color: [0, 0, 255], player: .track), .beat(0)])
        let none = try #require(quiet.preview(now: 0, timeAt: nil)).live
        #expect(none.beat == nil && none.phase == nil && none.needle == nil && none.meter == nil && none.time == nil)
    }

    @Test("The last minute while playing blinks off the time's arrival: red its first half second, then the other half")
    func look() throws {
        let state = Self.state([.deck(number: 1, color: [0, 0, 255], player: .track), .state([.loaded, .playing]),
                                .time(elapsedSeconds: 250, lengthSeconds: 293)])
        #expect(try #require(state.preview(now: 10.2, timeAt: 10)).live.look == .warningRed)
        #expect(try #require(state.preview(now: 10.7, timeAt: 10)).live.look == .warningNormal)
        #expect(try #require(state.preview(now: 11.1, timeAt: 10)).live.look == .warningRed)
    }

    @Test("No deck yet: nothing to draw")
    func noDeck() {
        #expect(Self.state([]).preview(now: 0, timeAt: nil) == nil)
    }
}
