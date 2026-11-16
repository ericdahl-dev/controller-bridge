import ControllerBridgePresentation
import Testing

/// The jog display simulator's words (#221), apart from the SwiftUI and the renderer.
@Suite("Jog display simulator")
struct JogSimulatorTests {
    @Test("VoiceOver hears each deck's display as one sentence: deck, title, key, BPM and beat")
    func spokenSummary() {
        #expect(JogDeckSummary(deck: 1, title: "Daybreak", key: "A#m", bpm: 128, beat: 2).spoken
            == "Deck 1, Daybreak, A#m, 128 BPM, beat 2")
        #expect(JogDeckSummary(deck: 3, title: "Night Drive", key: nil, bpm: 127.5, beat: nil).spoken
            == "Deck 3, Night Drive, 127.5 BPM")
        #expect(JogDeckSummary(deck: 2, title: nil, key: nil, bpm: nil, beat: nil).spoken == "Deck 2, no track loaded")
        #expect(JogDeckSummary(deck: 4, title: "", key: "C", bpm: 0, beat: 1).spoken == "Deck 4, no track loaded",
                "an empty title is an empty deck, as Syndicate sends it")
    }
}
