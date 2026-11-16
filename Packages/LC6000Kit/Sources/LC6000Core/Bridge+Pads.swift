// Pads, pad modes and cue colors (#18), as in the Python bridge.

/// What the eight pads do.
enum PadMode {
    case hotCue, roll, loop, slicer
}

extension Bridge {
    /// Slip roll sizes, pad 1 to pad 8.
    static let rollSizes = ["ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four"]

    /// A mode button. Switching mode first releases any held pad, so a hot cue or roll never sticks.
    func padModeButton(_ mode: PadMode) -> (Bool) -> Void {
        { pressed in
            guard pressed else { return }
            self.releasePads()
            self.padMode = mode
        }
    }

    /// Releases every held pad, and nothing else.
    func releasePads() {
        for index in mapping.notes.pads.indices { releaseHold(.pad(index)) }
    }

    /// A pad press or release. `index` is 0-7, so hot cue `index + 1`.
    func handlePad(_ index: Int, pressed: Bool) {
        guard pressed else { return releaseHold(.pad(index)) }
        let cue = Int32(index + 1)
        switch padMode {
        case .hotCue: hold(.pad(index), "HotCue", press: [.int(cue), .int(1)], release: [.int(cue), .int(0)])
        case .roll: hold(.pad(index), "SlipLoop/" + Self.rollSizes[index], press: [.int(1)], release: [.int(0)])
        case .loop: sendDeck("SetCueLoop", .int(cue))
        case .slicer: break
        }
    }
}
