// Continuous controls: the pitch fader, the jog wheel and the Needle Drop strip.

extension Bridge {
    func pitchMSB(_ value: UInt8) {
        pitchMSBValue = value
        sendPitch()
    }

    func pitchLSB(_ value: UInt8) {
        pitchLSBValue = value
        sendPitch()
    }

    private func sendPitch() {
        let t = tempoSlider(
            from: join14Bit(msb: pitchMSBValue, lsb: pitchLSBValue),
            invert: mapping.pitch.invert, deadZone: mapping.pitch.deadZone
        )
        let rounded = (t * 100_000).rounded() / 100_000
        guard rounded != lastTempo else { return }
        lastTempo = rounded
        sendDeck("TempoSlider", .float(Float(rounded)))
        refreshLEDs()
    }

    // MARK: Needle Drop

    /// The strip's absolute position, 0...127, as a seek across the whole track.
    func needle(_ value: UInt8) {
        guard needleTouched || !mapping.needle.requireTouch else { return }
        sendDeck("WaveformSeek", .float(Float(value) / 127))
    }

    // MARK: Jog

    func jog(_ value: UInt8) {
        let ticks = relativeTicks(value)
        guard ticks != 0, platterTouched || !mapping.jog.requireTouch else { return }
        lastJogTime = clock.now
        if playing {
            let direction = ticks > 0 ? 1 : -1
            guard direction != bendDirection else { return }
            bendDirection = direction
            hold(.bend, "PhaseBend", press: [.int(Int32(direction))], release: [.int(0)])
            return
        }
        // Paused: move the playhead.
        if let duration, let position = progress {
            let moved = min(1, max(0, position + Double(ticks) * mapping.jog.seekSecondsPerTick / duration))
            progress = moved
            sendDeck("WaveformSeek", .float(Float(moved)))
        } else {
            // No track length: skip whole beats, keeping the remainder for the next turn.
            seekTickRemainder += ticks
            let beats = seekTickRemainder / mapping.jog.seekFallbackTicksPerBeat
            guard beats != 0 else { return }
            seekTickRemainder -= beats * mapping.jog.seekFallbackTicksPerBeat
            sendDeck("BeatSkip", .int(Int32(beats)))
        }
    }

    func platterTouch(_ pressed: Bool) {
        platterTouched = pressed
        if !pressed, bendDirection != 0 { endBend() }
    }

    func tick() {
        if bendDirection != 0, clock.now - lastJogTime >= Double(mapping.jog.bendReleaseMs) / 1000 {
            endBend()
        }
    }

    func endBend() {
        bendDirection = 0
        releaseHold(.bend)
    }
}
