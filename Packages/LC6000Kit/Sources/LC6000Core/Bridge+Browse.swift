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
}
