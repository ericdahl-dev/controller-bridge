// Timing LEDs (#23): the pending-start blink and the beat pulse. Driven by tick, through the de-duplicating LED cache.

extension Bridge {
    /// How long the Play LED stays on, then off, while a start is pending.
    static let blinkHalfPeriod = 0.25
    /// With no master clock beat for this long (one beat at 30 BPM), the ring goes back to solid.
    static let clockTimeout = 2.0

    func timingTick() {
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
        led(mapping.leds.ring, lit ? Self.velocity(mapping.leds.ringColor) : Self.off)
    }
}
