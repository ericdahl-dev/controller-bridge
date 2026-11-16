import Foundation

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

/// The last upload to one deck's display, for the readout under its preview (#221), so the simulator doubles as a
/// display debugger.
public enum JogUploadStatus: Equatable, Sendable {
    /// No LC6000 is connected: the preview is drawn, nothing is sent.
    case notConnected
    /// Connected, but no image has been sent yet.
    case notUploaded
    /// An image went to `slot`, `bytes` long, and the unit accepted or refused it (JogDisplay.Reply).
    case uploaded(slot: Int, bytes: Int, at: Date, accepted: Bool)

    /// "Slot 2 · 14,812 bytes · 12:04:31 · Accepted". The time is local; tests pass a time zone.
    public func readout(timeZone: TimeZone = .current) -> String {
        switch self {
        case .notConnected: return "No LC6000 connected: preview only"
        case .notUploaded: return "Nothing uploaded yet"
        case .uploaded(let slot, let bytes, let at, let accepted):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let time = calendar.dateComponents([.hour, .minute, .second], from: at)
            let clock = [time.hour, time.minute, time.second].map { String(format: "%02d", $0 ?? 0) }.joined(separator: ":")
            return "Slot \(slot) · \(Self.grouped(bytes)) bytes · \(clock) · \(accepted ? "Accepted" : "Refused")"
        }
    }

    /// 14812 as "14,812", the same on every Mac whatever its region.
    private static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += "," }
            out.append(digit)
        }
        return out
    }
}
