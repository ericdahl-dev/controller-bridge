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
        // Moving the fader while Syndicate has the slider disabled would queue up a jump.
        guard sliderEnabled, pickedUp(at: rounded) else { return }
        guard rounded != lastTempo else { return }
        lastTempo = rounded
        recentTempoSends.removeAll { clock.now - $0.time > Self.echoWindow }
        recentTempoSends.append((clock.now, rounded))
        sendDeck("TempoSlider", .float(Float(rounded)))
        refreshLEDs()
    }

    // MARK: Pickup

    /// How long after a send its echo may still come back from Syndicate.
    static let echoWindow = 0.5

    /// Syndicate reported its TempoSlider. A value the bridge didn't send (sync, a mouse edit, another controller)
    /// moved the on-screen slider away from the fader, so pickup re-arms.
    func tempoReported(_ value: Double) {
        reportedTempo = value
        tempoWaitUntil = nil
        let tolerance = mapping.pitch.pickupTolerance
        let isEcho = lastTempo.map { abs($0 - value) <= tolerance } == true
            || recentTempoSends.contains { clock.now - $0.time <= Self.echoWindow && abs($0.value - value) <= tolerance }
        if !isEcho { rearmPickup() }
    }

    /// Dim while the fader waits to be picked up, so it can be caught by feel; otherwise full at the center.
    var pitchCenterVelocity: UInt8 {
        if mapping.pitch.pickup, pickupArmed, reportedTempo != nil { return Self.dim }
        return lastTempo == 0 ? Self.full : Self.off
    }

    func rearmPickup() {
        pickupArmed = true
        faderPosition = nil
        // Syndicate's slider may be anywhere now, so the pickup send goes out even if it repeats the last value.
        lastTempo = nil
    }

    /// Whether the fader at `position` drives the tempo. While armed it doesn't, until it comes within tolerance of
    /// the reported value or moves across it. With no report yet there is nothing to meet, so the fader passes
    /// through, except just after a deck switch, when it waits for the new deck's report (`tempoWaitUntil`).
    private func pickedUp(at position: Double) -> Bool {
        guard mapping.pitch.pickup, pickupArmed else { return true }
        guard let reported = reportedTempo else {
            if let until = tempoWaitUntil, clock.now < until { return false }
            return true
        }
        let previous = faderPosition
        faderPosition = position
        let near = abs(position - reported) <= mapping.pitch.pickupTolerance
        let crossed = previous.map { ($0 - reported) * (position - reported) < 0 } ?? false
        guard near || crossed else { return false }
        pickupArmed = false
        return true
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
        timingTick()
    }

    func endBend() {
        bendDirection = 0
        releaseHold(.bend)
    }
}
