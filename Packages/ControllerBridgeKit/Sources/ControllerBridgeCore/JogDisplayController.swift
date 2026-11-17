// The jog display controller (#384): which deck the LC6000's jog display shows, each deck's needle, and the driver
// behind JogDisplayPort, from plain values per controller entry. The Coordinator only forwards to it; it reads no
// Bridge internals, only each Bridge's DeckFacts (#383).

final class JogDisplayController {
    private let clock: any Clock
    /// Each entry's needle: its deck's own phase in the bar (#165).
    private var needles: [Int: JogMarker] = [:]
    /// What each entry's facts said last, to see a new BarRamp and a deck that stops.
    private var lastRamp: [Int: DeckFacts.BarRamp] = [:]
    private var lastPlaying: [Int: Bool] = [:]
    /// Syndicate's master tempo, for a deck whose own BPM isn't known yet.
    private(set) var masterBPM: Double?

    init(clock: any Clock) {
        self.clock = clock
    }

    /// Syndicate's header feedback: the master tempo (and, for the ring, the master beat).
    func feedback(_ message: OSCMessage) {
        let address = message.address.lowercased()
        if address.hasSuffix("/header/bpm"), let bpm = message.arguments.first?.number, bpm > 0 { masterBPM = bpm }
    }

    /// Each entry's facts, after Syndicate's feedback: a deck that stops keeps its needle where it is, and a new
    /// BarRamp sets it, running on at the deck's tempo while it plays (the platter never moves it, #388).
    func observe(_ entries: [Entry]) {
        for (index, entry) in entries.enumerated() {
            let facts = entry.facts
            if lastPlaying[index] == true, !facts.playing { needles[index]?.freeze(at: clock.now) }
            lastPlaying[index] = facts.playing
            if let ramp = facts.barRamp, ramp != lastRamp[index] {
                lastRamp[index] = ramp
                let bpm = facts.playing ? facts.bpm ?? masterBPM ?? 120 : 0
                needles[index, default: JogMarker()].ramp(ramp.phase, bpm: bpm, at: ramp.at)
            }
        }
    }

    /// An entry's needle as pitch bend at `time`.
    func needle(_ index: Int, at time: Double) -> Int {
        (needles[index] ?? JogMarker()).pitchBend(at: time)
    }

    /// What the controller knows of one controller entry, in the Coordinator's order.
    struct Entry: Equatable {
        /// The entry's MIDI input is open.
        var connected: Bool
        /// Its profile excludes a WD port that's present: the display is its (#305).
        var ownsDisplay: Bool
        /// It's the active layer of its controller.
        var activeLayer: Bool
        var facts: DeckFacts
    }

    /// The entry whose deck the display shows. Connected: an entry that owns the display comes first, then the active
    /// layer, else the first. With none connected, the preview's (#221): the picked deck's, else the first loaded one's,
    /// else the first.
    static func front(_ entries: [Entry], previewDeck: Int?) -> Int? {
        let connected = entries.indices.filter { entries[$0].connected }
        if !connected.isEmpty {
            let owners = connected.filter { entries[$0].ownsDisplay }
            let candidates = owners.isEmpty ? connected : owners
            return candidates.first { entries[$0].activeLayer } ?? candidates.first
        }
        if let pick = previewDeck, let index = entries.indices.first(where: { entries[$0].facts.deck == pick }) { return index }
        return entries.indices.first { entries[$0].facts.loaded } ?? entries.indices.first
    }
}
