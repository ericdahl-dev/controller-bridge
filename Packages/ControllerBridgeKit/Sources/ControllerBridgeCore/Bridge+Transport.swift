// Transport buttons: Play, Cue, Sync, Master, Censor, Key Lock, Slip, Pitch Bend − / + and Shift.
// Triggers fire on press only; holds send 1, then 0.

extension Bridge {
    func play(_ pressed: Bool) {
        // Play wins over a Shift + pad tap still waiting to be paused (#358).
        guard pressed else { return }
        endCueJump()
        // PLAY while CUE is held keeps the preview playing once CUE is let go, as on a CDJ (#360): set, not toggled.
        if cueDown { return sendDeck("Playing", .int(1)) }
        sendDeck("PlayPause", .int(1))
    }

    func sync(_ pressed: Bool) {
        if pressed { sendDeck("TempoSync", .int(1)) }
    }

    func master(_ pressed: Bool) {
        if pressed { sendDeck("TempoMaster", .int(1)) }
    }

    /// Pitch Bend − (#114): nudges the tempo down while held.
    func pitchMinus(_ pressed: Bool) {
        if shift { pitchRange(pressed) } else { holdButton(.phaseMinus, "PhaseMinus", pressed: pressed) }
    }

    /// Pitch Bend + (#114): nudges the tempo up while held.
    func pitchPlus(_ pressed: Bool) {
        if shift { pitchRange(pressed) } else { holdButton(.phasePlus, "PhasePlus", pressed: pressed) }
    }

    /// Shift + Pitch Bend is the LC6000's pitch range. Syndicate has no OSC route for the slider's range, so it sends
    /// nothing and says so once in the log (#114).
    private func pitchRange(_ pressed: Bool) {
        guard pressed, !pitchRangeNoted else { return }
        pitchRangeNoted = true
        notices.append("Pitch range (Shift + Pitch Bend) isn't available in Syndicate")
    }

    func shiftButton(_ pressed: Bool) {
        shift = pressed
        refreshLEDs()
    }

    /// Key Lock toggles key lock; Shift + Key Lock is the LC6000's pitch reset, sent as a tempo reset (#114).
    func keyLock(_ pressed: Bool) {
        guard pressed else { return }
        if shift { return resetTempo() }
        keyLockOn.toggle()
        sendDeck("PitchPreserve", .int(keyLockOn ? 1 : 0))
        refreshLEDs()
    }

    func slip(_ pressed: Bool) {
        guard pressed else { return }
        slipOn.toggle()
        sendDeck("CueSlip", .int(slipOn ? 1 : 0))
        refreshLEDs()
    }

    /// CUE is Syndicate's own: back to the cue point and stop while playing, preview while held on it, and a new cue
    /// point when paused elsewhere. Shift + CUE goes back to the cue point and stops (#360), and never sets one.
    func cue(_ pressed: Bool) {
        if pressed, shift {
            shiftCueDown = true
            if playing { return holdButton(.cue, "Cue", pressed: true) }
            return returnToMainCue()
        }
        if !pressed, shiftCueDown {
            shiftCueDown = false
            return holdButton(.cue, "Cue", pressed: false)
        }
        cueDown = pressed
        if pressed {
            // Syndicate's cue point is where it's paused, or, while playing, where it stops.
            if playing { mainCueSettlesUntil = clock.now + Self.mainCueSettle } else if let lastPosition { mainCue = lastPosition }
        }
        holdButton(.cue, "Cue", pressed: pressed)
    }

    /// How long after CUE-while-playing the deck's stop says where the cue point is.
    static let mainCueSettle = 0.5
    /// Closer than this to the cue point is on it.
    static let onCuePoint = 0.02

    /// Shift + CUE on a paused deck: a WaveformSeek to the cue point, with quantize None so it lands there at once.
    /// Unknown, or already there: nothing, since Syndicate's Cue would make this spot the cue point.
    private func returnToMainCue() {
        guard let mainCue, let lastPosition, let duration, duration > 0, abs(lastPosition - mainCue) > Self.onCuePoint else { return }
        overrideQuantize(.returnToCue)
        sendDeck("WaveformSeek", .float(Float(mainCue / duration)))
        restoreQuantize(.returnToCue)
    }

    /// Where the deck is, from Syndicate's Position: after CUE while playing, the paused spot is the cue point.
    func positionReported(_ seconds: Double) {
        lastPosition = seconds
        guard !playing, let until = mainCueSettlesUntil else { return }
        mainCueSettlesUntil = nil
        if clock.now <= until { mainCue = seconds }
    }

    /// The deck stopped: right after CUE while playing, it stopped on the cue point.
    func mainCueStopped() {
        guard let until = mainCueSettlesUntil, clock.now <= until, let lastPosition else { return }
        mainCue = lastPosition
    }

    /// Censor reverses while held. Shift + Censor latches Reverse instead: each press toggles it (#114). A latched
    /// Reverse isn't a hold, but release-all still turns it off.
    func censor(_ pressed: Bool) {
        if pressed, shift {
            if let address = latchedReverse {
                send(address: address, [.int(0)])
                latchedReverse = nil
            } else {
                let address = deckAddress("Reverse")
                send(address: address, [.int(1)])
                latchedReverse = address
            }
            return
        }
        guard pressed || held.contains(.censor) else { return }
        holdButton(.censor, "Reverse", pressed: pressed)
        // The hold's release turned Reverse off in Syndicate, latched or not.
        if !pressed { latchedReverse = nil }
    }

    // MARK: Holds

    /// A hold whose press sends 1 and whose release sends 0.
    func holdButton(_ key: HoldKey, _ path: String, pressed: Bool) {
        if pressed {
            hold(key, path, press: [.int(1)], release: [.int(0)])
        } else {
            releaseHold(key)
        }
    }

    /// Sends the press, and records the release with this deck's full address.
    func hold(_ key: HoldKey, _ path: String, press: [OSCArgument], release: [OSCArgument]) {
        let address = deckAddress(path)
        send(address: address, press)
        held.record(key, HeldControl(deck: mapping.deck.number, address: address, release: release))
    }

    /// Sends every recorded release once, then forgets them. Quit, unplug, sleep, a deck or device change and a
    /// mapping import all come through here.
    func releaseAll() {
        endCueJump()
        restoreAllQuantize()
        for control in held.takeAll() { send(address: control.address, control.release) }
        if let address = latchedReverse {
            send(address: address, [.int(0)])
            latchedReverse = nil
        }
        bendDirection = 0
        cueDown = false
        shiftCueDown = false
        platterTouched = false
        needleTouched = false
        if shift {
            shift = false
            refreshLEDs()
        }
    }

    func releaseHold(_ key: HoldKey) {
        guard let control = held.take(key) else { return }
        send(address: control.address, control.release)
    }
}

// MARK: LEDs

extension Bridge {
    /// The deck is Syndicate's tempo master: synced, with its tempo slider enabled. The Master LED and the status share it.
    var isMaster: Bool { synced && sliderEnabled }

    /// The transport LEDs: Cue, Sync and Master follow Syndicate; Key Lock, Slip and Shift show the bridge's state.
    func refreshTransportLEDs() {
        buttonLED("cue", on: loaded && !playing)
        buttonLED("sync", on: synced)
        buttonLED("master", on: isMaster)
        buttonLED("key_lock", on: keyLockOn)
        buttonLED("slip", on: slipOn)
        buttonLED("shift", on: shift)
    }
}
