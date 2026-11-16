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
        if pressed { send("Browser/L\(mapping.deck.number)", .int(1)) }
    }

    /// One browser step per tick.
    func selectTurn(_ value: UInt8) {
        let ticks = relativeTicks(value)
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
    func autoLoopSize(_ value: UInt8) {
        let ticks = relativeTicks(value)
        if ticks != 0 { sendDeck(ticks > 0 ? "LoopOut" : "LoopIn", .int(1)) }
    }

    // MARK: Jumps

    func beatJumpBack(_ pressed: Bool) {
        if pressed { sendDeck("SkipBeatBack", .int(1)) }
    }

    func beatJumpForward(_ pressed: Bool) {
        if pressed { sendDeck("SkipBeatForward", .int(1)) }
    }

    func paramBack(_ pressed: Bool) {
        if pressed { sendDeck("BeatSkip", .int(-1)) }
    }

    func paramForward(_ pressed: Bool) {
        if pressed { sendDeck("BeatSkip", .int(1)) }
    }
}
