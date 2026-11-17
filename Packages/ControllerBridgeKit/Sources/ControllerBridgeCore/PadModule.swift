/// The Bridge's pads as a module (#383 slice 5): the pad mode and which note plays which pad (#18, #198, #225).
/// Plain values in, sends out; the Bridge applies them (holds, OSC, LEDs), as CueModule (#408) does.
struct PadModule {
    enum Send: Equatable, Sendable {
        /// Let every held pad go (a mode change), so a hot cue or roll never sticks.
        case releasePads
    }

    private let pads: Mapping.Pads
    /// `notes.pads`: the notes the pads send in every mode, unless the profile gives each mode its own (#225).
    private let padNotes: [Int]
    private(set) var mode = PadMode.hotCue

    init(mapping: Mapping) {
        pads = mapping.pads
        padNotes = mapping.notes.pads
    }

    /// The bridge's own state across a settings swap (#115): the pad mode.
    mutating func carry(from old: PadModule) {
        mode = old.mode
    }

    /// A mode button (pressed): held pads go, then the mode switches.
    mutating func modeButton(_ mode: PadMode) -> [Send] {
        self.mode = mode
        return [.releasePads]
    }

    /// The one cycling mode button (#198), for a profile whose `pads.mode_select` is "cycle"; with the LC6000's four
    /// buttons it does nothing.
    mutating func cycle() -> [Send] {
        guard pads.modeSelect == .cycle else { return [] }
        mode = mode.next
        return [.releasePads]
    }

    /// The pad a note plays, and on a profile with notes per mode (#225) the mode that note belongs to.
    func pad(for note: Int) -> (index: Int, mode: PadMode?)? {
        guard let modeNotes = pads.modeNotes else { return padNotes.firstIndex(of: note).map { ($0, nil) } }
        for mode in PadMode.allCases {
            if let index = notes(for: mode, modeNotes).firstIndex(of: note) { return (index, mode) }
        }
        return nil
    }

    /// A pad note pressed: its pad, after switching to the note's own mode (#225) when that's another one, which lets
    /// held pads go as a mode button does. Nil for a note that isn't a pad's.
    mutating func press(note: Int) -> (index: Int, sends: [Send])? {
        guard let (index, noteMode) = pad(for: note) else { return nil }
        guard let noteMode, noteMode != mode else { return (index, []) }
        mode = noteMode
        return (index, [.releasePads])
    }

    /// The notes the pads send and light in `mode`: that mode's list (#225), or `notes.pads` for every mode.
    func notes(for mode: PadMode) -> [Int] {
        guard let modeNotes = pads.modeNotes else { return padNotes }
        return notes(for: mode, modeNotes)
    }

    private func notes(for mode: PadMode, _ modeNotes: Mapping.Pads.ModeNotes) -> [Int] {
        switch mode {
        case .hotCue: modeNotes.hotcue
        case .roll: modeNotes.roll
        case .loop: modeNotes.loop
        case .slicer: modeNotes.slicer
        }
    }

    /// Every note of every mode's own list (#225): the ones to darken when they're not the current mode's.
    var allModeNotes: [Int] {
        guard let modeNotes = pads.modeNotes else { return [] }
        return modeNotes.hotcue + modeNotes.roll + modeNotes.loop + modeNotes.slicer
    }
}
