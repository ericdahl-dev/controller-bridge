// Transport buttons: Play, Cue, Sync, Master, Censor, Key Lock, Slip, Pitch − / + and Shift.
// Triggers fire on press only; holds send 1, then 0.

extension Bridge {
    func play(_ pressed: Bool) {
        if pressed { sendDeck("PlayPause", .int(1)) }
    }

    func sync(_ pressed: Bool) {
        if pressed { sendDeck("TempoSync", .int(1)) }
    }

    func master(_ pressed: Bool) {
        if pressed { sendDeck("TempoMaster", .int(1)) }
    }

    func pitchMinus(_ pressed: Bool) {
        if pressed { sendDeck(shift ? "PitchReset" : "PitchDown", .int(1)) }
    }

    func pitchPlus(_ pressed: Bool) {
        if pressed { sendDeck(shift ? "PitchReset" : "PitchUp", .int(1)) }
    }

    func shiftButton(_ pressed: Bool) {
        shift = pressed
        refreshLEDs()
    }

    func keyLock(_ pressed: Bool) {
        guard pressed else { return }
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

    func cue(_ pressed: Bool) {
        holdButton(.cue, "Cue", pressed: pressed)
    }

    func censor(_ pressed: Bool) {
        holdButton(.censor, "Reverse", pressed: pressed)
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
        for control in held.takeAll() { send(address: control.address, control.release) }
        bendDirection = 0
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
    /// The transport LEDs: Cue, Sync and Master follow Syndicate; Key Lock, Slip and Shift show the bridge's state.
    func refreshTransportLEDs() {
        buttonLED("cue", on: loaded && !playing)
        buttonLED("sync", on: synced)
        buttonLED("master", on: synced && sliderEnabled)
        buttonLED("key_lock", on: keyLockOn)
        buttonLED("slip", on: slipOn)
        buttonLED("shift", on: shift)
    }
}
