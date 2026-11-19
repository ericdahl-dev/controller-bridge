// Timing LEDs (#23): the pending-start blink and the beat pulse. Driven by tick, through the de-duplicating LED cache.

extension Bridge {
    /// How long the Play LED stays on, then off, while a start is pending.
    static let blinkHalfPeriod = 0.25
    /// With no master clock beat for this long (one beat at 30 BPM), the ring goes back to solid.
    static let clockTimeout = 2.0

    func timingTick() {
        colorTick()
        playLED()
        ringLED()
    }

    /// Full while playing. While a quantized start is pending, it blinks on the clock.
    func playLED() {
        let blinkOn = Int((clock.now / Self.blinkHalfPeriod).rounded(.down)) % 2 == 0
        buttonLED("play", on: playing || (playPending && blinkOn))
    }

    /// Syndicate's master clock (not this deck's own beat): beat-in-bar 1-4 on every master beat.
    func headerClock(_ arguments: [OSCArgument]) {
        lastClockTime = clock.now
        switch mapping.leds.beatPulse {
        case .off: return
        case .beat: break
        case .downbeat: guard arguments.first?.wholeNumber == 1 else { return }
        }
        lastPulseTime = clock.now
        ringLED()
    }

    /// Lit while a track is loaded. With beat pulse on and a clock arriving, lit only for `pulse_ms` after each beat.
    func ringLED() {
        var lit = loaded
        if let pulse = lastPulseTime, let beat = lastClockTime, clock.now - beat <= Self.clockTimeout {
            lit = lit && clock.now - pulse < Double(mapping.leds.pulseMs) / 1000
        }
        let on = lit && !ringHeld
        if let message = colorMessageEncoder?.message(note: mapping.leds.ring, rgb: on ? ringColor : [0, 0, 0]) {
            return colorLED(message)
        }
        led(mapping.leds.ring, on ? ringVelocity(ringColor) : Self.off)
    }

    /// Settings (#530): the color message on or off; the ring and pads repaint.
    func setColorMessages(_ on: Bool) {
        guard on != colorMessages else { return }
        colorMessages = on
        // From scratch: on the unit, a color message and a note-on each replace what the other showed.
        repaintLEDs()
    }

    /// Vivid or exact (#151): the ring and pads repaint.
    func setRingColors(_ mode: RingColors) {
        ringColors = mode
        refreshLEDs()
    }

    /// New deck colors (#123): the ring repaints in its deck's.
    func setDeckColors(_ colors: DeckColors) {
        deckColors = colors
        ringLED()
    }

    /// The deck's badge color, so the ring shows which deck this layer drives (#122).
    var ringColor: [Int] {
        guard mapping.leds.ringFollowsDeck, let deck = deckColors[mapping.deck.number] else { return mapping.leds.ringColor }
        return deck
    }
}
