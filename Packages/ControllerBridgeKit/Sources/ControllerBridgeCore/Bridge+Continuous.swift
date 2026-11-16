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
        let pitch = mapping.pitch
        // A 7-bit fader is one CC (#195); the LC6000's is an MSB/LSB pair.
        let t = pitch.bits == 7
            ? tempoSlider(from7Bit: pitchMSBValue, invert: pitch.invert, deadZone: pitch.deadZone)
            : tempoSlider(from: join14Bit(msb: pitchMSBValue, lsb: pitchLSBValue), invert: pitch.invert, deadZone: pitch.deadZone)
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

    /// Sets Syndicate's tempo slider to 0.0, then waits for the fader to come back to 0.0 so it doesn't jump the tempo
    /// back to where the fader sits (#114). A synced follower's slider is disabled, and Syndicate ignores TempoSlider
    /// then, so nothing is sent.
    func resetTempo() {
        guard sliderEnabled else { return }
        rearmPickup()
        reportedTempo = 0
        tempoWaitUntil = nil
        // Syndicate's answer is the echo of this send, not an outside change.
        recentTempoSends.removeAll { clock.now - $0.time > Self.echoWindow }
        recentTempoSends.append((clock.now, 0))
        sendDeck("TempoSlider", .float(0))
        refreshLEDs()
    }

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
        if mapping.pitch.pickup, pickupArmed, reportedTempo != nil { return dimLevel }
        return lastTempo == 0 ? fullLevel : offLevel
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

    func needleMSB(_ value: UInt8) {
        needleMSBValue = value
    }

    /// The strip's 14-bit position (#103), as a seek across the whole track. Sent when the LSB arrives, so an MSB on
    /// its own never seeks to a half-updated place.
    func needleLSB(_ value: UInt8) {
        guard needleTouched || !mapping.needle.requireTouch else { return }
        let position = join14Bit(msb: needleMSBValue, lsb: value)
        sendDeck("WaveformSeek", .float(Float(Double(position) / 16383)))
    }

    // MARK: Jog

    func jogMSB(_ value: UInt8) {
        jogMSBValue = value
    }

    /// The platter's 14-bit position (#103). Movement is the change since the last position, taking the shorter way
    /// around the wrap at 16384, so 16376 → 3 is 11 forward. Read when the LSB arrives, so an MSB carry never jumps.
    func jogLSB(_ value: UInt8) {
        let position = join14Bit(msb: jogMSBValue, lsb: value)
        defer { jogPosition = position }
        guard let previous = jogPosition else { return }
        var counts = (position - previous) % 16384
        if counts > 8192 { counts -= 16384 } else if counts < -8192 { counts += 16384 }
        jog(counts: counts)
    }

    /// A relative jog's tick on the platter's top (#204), in the profile's encoder format.
    func jogRelative(_ value: UInt8) {
        jog(counts: mapping.midi.encoderFormat.ticks(value))
    }

    /// A relative jog's tick on the platter's edge (#204): it moves without a touch.
    func jogRelativeEdge(_ value: UInt8) {
        jog(counts: mapping.midi.encoderFormat.ticks(value), needsTouch: false)
    }

    private func jog(counts: Int, needsTouch: Bool = true) {
        guard counts != 0, platterTouched || !mapping.jog.requireTouch || !needsTouch else { return }
        jogCountsPending += counts
        lastJogTime = clock.now
        if playing {
            let direction = counts > 0 ? 1 : -1
            guard direction != bendDirection else { return }
            bendDirection = direction
            hold(.bend, "PhaseBend", press: [.int(Int32(direction))], release: [.int(0)])
            return
        }
        // The check keeps these positive; a hand-built mapping with 0 mustn't trap (#92).
        let countsPerRev = Double(mapping.jog.countsPerRev)
        guard countsPerRev > 0 else { return }
        let revolutions = Double(counts) / countsPerRev
        // Paused: move the playhead.
        if let duration, let position = progress {
            let moved = min(1, max(0, position + revolutions * mapping.jog.seekSecondsPerRev / duration))
            progress = moved
            sendDeck("WaveformSeek", .float(Float(moved)))
        } else {
            // No track length: skip whole beats, keeping the remainder for the next turn.
            let countsPerBeat = Int((countsPerRev / mapping.jog.beatsPerRev).rounded())
            guard countsPerBeat > 0 else { return }
            seekCountRemainder += counts
            let beats = seekCountRemainder / countsPerBeat
            guard beats != 0 else { return }
            seekCountRemainder -= beats * countsPerBeat
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
