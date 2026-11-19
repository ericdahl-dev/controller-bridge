/// What a Bridge knows of its Syndicate deck, from Syndicate's feedback (#383), as one read-only value. The
/// Coordinator, the jog display (#384) and the Bridge's own modules read this, not the Bridge's variables.
struct DeckFacts: Equatable, Sendable {
    struct Track: Equatable, Sendable {
        var title: String
        var artist: String
        var key: String
        var bpm: Double
        var playerType: String
    }

    /// The deck's latest BarRamp (#165): the phase through the bar, 0–1, and when it arrived.
    struct BarRamp: Equatable, Sendable {
        var phase: Double
        var at: Double
    }

    /// Syndicate's deck number, 1–4.
    var deck: Int
    var playing = false
    var loaded = false
    /// A quantized start is waiting (#459).
    var playPending = false
    /// The live tempo, from the deck's BPM.
    var bpm: Double?
    var track: Track?
    /// The track's length in seconds, from TrackInfo.
    var duration: Double?
    /// Where the deck is, in seconds, from Position.
    var position: Double?
    var barRamp: BarRamp?
}

extension Bridge {
    var facts: DeckFacts {
        DeckFacts(
            deck: mapping.deck.number, playing: playing, loaded: loaded, playPending: playPending, bpm: bpm,
            track: track.map { DeckFacts.Track(title: $0.title, artist: $0.artist, key: $0.key, bpm: $0.bpm, playerType: $0.playerType) },
            duration: duration, position: cueMemory.position, barRamp: barRamp
        )
    }
}
