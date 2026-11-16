// Timing LEDs (#23): the pending-start blink. Driven by tick, through the de-duplicating LED cache.

extension Bridge {
    /// How long the Play LED stays on, then off, while a start is pending.
    static let blinkHalfPeriod = 0.25

    func timingTick() {
        playLED()
    }

    /// Full while playing. While a quantized start is pending, it blinks on the clock.
    func playLED() {
        let blinkOn = Int((clock.now / Self.blinkHalfPeriod).rounded(.down)) % 2 == 0
        buttonLED("play", on: playing || (playPending && blinkOn))
    }
}
