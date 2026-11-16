// Feedback liveness (#21): what a Bridge forgets when Syndicate's feedback stops.

extension Bridge {
    /// Forgets everything learned from Syndicate's feedback, so its LEDs show idle, not a track that may be gone.
    /// The bridge's own state (Shift, Key Lock, Slip, the pad mode, held controls) stays.
    func clearSyndicateState() {
        playing = false
        playPending = false
        loaded = false
        synced = false
        sliderEnabled = true
        looping = false
        cues = [Int](repeating: 0, count: 8)
        progress = nil
        duration = nil
        lastPulseTime = nil
        lastClockTime = nil
        refreshLEDs()
    }
}
