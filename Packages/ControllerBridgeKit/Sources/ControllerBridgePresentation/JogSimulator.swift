/// The jog display simulator's words (#221): Diagnostics › Jog display draws each deck's display from the same
/// renderer as the hardware upload (#165); these are the parts around the picture.

/// What one deck's display shows, as VoiceOver reads it: the picture itself says nothing to a screen reader.
public struct JogDeckSummary: Equatable, Sendable {
    public var deck: Int
    public var title: String?
    public var key: String?
    public var bpm: Double?
    public var beat: Int?

    public init(deck: Int, title: String?, key: String?, bpm: Double?, beat: Int?) {
        self.deck = deck
        self.title = title
        self.key = key
        self.bpm = bpm
        self.beat = beat
    }

    /// "Deck 1, Daybreak, A#m, 128 BPM, beat 2", leaving out what isn't known. An empty title is an empty deck, as
    /// Syndicate's TrackInfo sends it (#209).
    public var spoken: String {
        guard let title, !title.isEmpty else { return "Deck \(deck), no track loaded" }
        var parts = ["Deck \(deck)", title]
        if let key, !key.isEmpty { parts.append(key) }
        if let bpm, bpm > 0 {
            parts.append((bpm.rounded() == bpm ? String(Int(bpm)) : String(bpm)) + " BPM")
        }
        if let beat { parts.append("beat \(beat)") }
        return parts.joined(separator: ", ")
    }
}
