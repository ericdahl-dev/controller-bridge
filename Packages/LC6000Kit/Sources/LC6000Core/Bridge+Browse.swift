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
}
