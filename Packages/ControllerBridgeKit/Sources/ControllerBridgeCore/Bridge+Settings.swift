// Settings changes (#19) that reach a running Bridge.

extension Bridge {
    /// Drives another Syndicate deck. Everything held is released on the old deck first, and what was known about the
    /// old deck is forgotten, so nothing from it shows on the new one. The caller resyncs.
    func switchDeck(to deck: Int) {
        releaseAll()
        mapping.deck.number = deck
        clearSyndicateState()
        // Feedback is still arriving; only the deck changed.
        feedbackStale = false
        reportedTempo = nil
        start()
    }
}
