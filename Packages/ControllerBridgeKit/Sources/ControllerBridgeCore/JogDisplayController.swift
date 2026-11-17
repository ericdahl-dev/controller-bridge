// The jog display controller (#384): which deck the LC6000's jog display shows, each deck's needle, and the driver
// behind JogDisplayPort, from plain values per controller entry. The Coordinator only forwards to it; it reads no
// Bridge internals, only each Bridge's DeckFacts (#383).

final class JogDisplayController {
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
