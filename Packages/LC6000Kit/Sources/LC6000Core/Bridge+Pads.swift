// Pads, pad modes and cue colors (#18), as in the Python bridge.

extension Bridge {
    /// A pad press or release. `index` is 0-7, so hot cue `index + 1`.
    func handlePad(_ index: Int, pressed: Bool) {
        guard pressed else { return releaseHold(.pad(index)) }
        let cue = Int32(index + 1)
        hold(.pad(index), "HotCue", press: [.int(cue), .int(1)], release: [.int(cue), .int(0)])
    }
}
