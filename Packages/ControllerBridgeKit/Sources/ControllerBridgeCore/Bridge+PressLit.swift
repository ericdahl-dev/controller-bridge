// The dark buttons (#476): buttons with no state to show are lit dim when idle, so the panel reads in the dark, and
// full while held, so every press shows. They're the bridge's own lights, not Syndicate's.

extension Bridge {
    /// Beat Jump, Track Skip, the browse knob's ring (its press), Vinyl, Pitch Bend and Param. A profile that doesn't
    /// name one has no light for it.
    static let pressLitButtons = ["beat_jump_back", "beat_jump_forward", "track_prev", "track_next", "select_press",
                                  "vinyl", "pitch_minus", "pitch_plus", "param_back", "param_forward"]

    /// Lit at their idle level only, never full: the deck select button (#477). On the unit a press showed no brighter
    /// level (it seems to own that light while the button is down; #480's live check), so a press sends it nothing.
    static let idleLitButtons = ["deck_select"]

    /// Each one's light: full while held, else idle; the idle-only ones idle.
    func pressLitLEDs() {
        for name in Self.pressLitButtons { buttonLED(name, on: pressLitHeld.contains(name)) }
        for name in Self.idleLitButtons { buttonLED(name, on: false) }
    }

    /// A press or release of a button: one of these lights full while it's held.
    func pressLit(_ name: String, _ pressed: Bool) {
        guard Self.pressLitButtons.contains(name) else { return }
        if pressed { pressLitHeld.insert(name) } else { pressLitHeld.remove(name) }
        buttonLED(name, on: pressed)
    }
}
