// The dark buttons (#476): buttons with no state to show are lit dim when idle, so the panel reads in the dark, and
// full while held, so every press shows. They're the bridge's own lights, not Syndicate's.

extension Bridge {
    /// Beat Jump, Track Skip, the browse knob's ring (its press), Vinyl, Pitch Bend and Param. A profile that doesn't
    /// name one has no light for it.
    static let pressLitButtons = ["beat_jump_back", "beat_jump_forward", "track_prev", "track_next", "select_press",
                                  "vinyl", "pitch_minus", "pitch_plus", "param_back", "param_forward"]

    /// Each one's light: full while held, else idle.
    func pressLitLEDs() {
        for name in Self.pressLitButtons { buttonLED(name, on: false) }
    }
}
