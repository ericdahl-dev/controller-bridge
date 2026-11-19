// Browse, loop and jump controls (#16), as in the Python bridge.

extension Bridge {
    // MARK: Browser

    func trackPrevious(_ pressed: Bool) {
        if pressed { send("Browser/Up", .int(1)) }
    }

    func trackNext(_ pressed: Bool) {
        if pressed { send("Browser/Down", .int(1)) }
    }

    func browserBack(_ pressed: Bool) {
        if pressed { send("Browser/Back", .int(1)) }
    }

    func browserForward(_ pressed: Bool) {
        if pressed { send("Browser/Enter", .int(1)) }
    }

    func selectPress(_ pressed: Bool) {
        if pressed { send(shift ? "Browser/Enter" : "Browser/L\(mapping.deck.number)", .int(1)) }
    }

    /// One browser step per tick.
    func selectTurn(_ value: UInt8) {
        let ticks = mapping.midi.encoderFormat.ticks(value)
        for _ in 0..<abs(ticks) { send(ticks > 0 ? "Browser/Down" : "Browser/Up", .int(1)) }
    }

    // MARK: Loops

    func loopIn(_ pressed: Bool) {
        if pressed { sendDeck("LoopIn", .int(1)) }
    }

    func loopOut(_ pressed: Bool) {
        if pressed { sendDeck("LoopOut", .int(1)) }
    }

    func autoLoop(_ pressed: Bool) {
        if pressed { sendDeck("Loop", .int(1)) }
    }

    /// While looping, Syndicate's LoopOut doubles the loop and LoopIn halves it. One step per turn, however fast.
    /// With Shift held it's the knob's printed Loop Move (#470): the loop moves a beat per click, forward clockwise.
    func autoLoopSize(_ value: UInt8) {
        let ticks = mapping.midi.encoderFormat.ticks(value)
        guard ticks != 0 else { return }
        if shift {
            for _ in 0..<abs(ticks) { sendDeck("LoopMoveBeat", .int(ticks > 0 ? 1 : -1)) }
        } else {
            sendDeck(ticks > 0 ? "LoopOut" : "LoopIn", .int(1))
        }
    }

    // MARK: Jumps

    func beatJumpBack(_ pressed: Bool) {
        if pressed { sendDeck(shift ? "SkipBarBack" : "SkipBeatBack", .int(1)) }
    }

    func beatJumpForward(_ pressed: Bool) {
        if pressed { sendDeck(shift ? "SkipBarForward" : "SkipBeatForward", .int(1)) }
    }

    func paramBack(_ pressed: Bool) {
        if pressed { sendDeck("BeatSkip", .int(-1)) }
    }

    func paramForward(_ pressed: Bool) {
        if pressed { sendDeck("BeatSkip", .int(1)) }
    }

    // MARK: LEDs

    /// The three loop buttons light together while Syndicate reports a loop.
    func loopLEDs() {
        for name in ["loop_in", "loop_out", "auto_loop"] { buttonLED(name, on: looping) }
    }
}
