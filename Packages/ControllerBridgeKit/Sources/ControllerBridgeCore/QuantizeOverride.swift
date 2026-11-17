import Foundation

/// "Quantize None while X, restore Use Global after" (#366), one per deck. Syndicate quantizes seeks and cue launches
/// while a deck's Q is on (User Guide 14.6), and doesn't report a deck's quantize, so DeckBridge turns it off while it
/// needs exact, immediate moves and back to Use Global after (the user's pick, #363: a deck's own setting is reset).
/// Several reasons can overlap; only the first in and the last out change anything, so none restores early.
struct QuantizeOverride: Equatable, Sendable {
    enum Reason: Hashable, Sendable {
        /// Shift + hot cue pad on a stopped deck (#358, #363).
        case cueJump
        /// The jog or needle strip seeking a paused deck (#366).
        case jogSeek
        /// CUE on a paused deck going back to the cue point (#360).
        case returnToCue
    }

    /// What to send to the deck's Quantize: None (1) or Use Global (0).
    enum Change: Equatable, Sendable {
        case none, useGlobal
        var value: Int32 { self == .none ? 1 : 0 }
    }

    private var reasons: Set<Reason> = []

    var isHeld: Bool { !reasons.isEmpty }
    func holds(_ reason: Reason) -> Bool { reasons.contains(reason) }

    /// `reason` needs quantize off: `.none` to send if it was on.
    mutating func acquire(_ reason: Reason) -> Change? {
        let wasHeld = isHeld
        reasons.insert(reason)
        return wasHeld ? nil : Change.none
    }

    /// `reason` is done: `.useGlobal` to send if it was the last.
    mutating func release(_ reason: Reason) -> Change? {
        guard reasons.remove(reason) != nil, reasons.isEmpty else { return nil }
        return .useGlobal
    }

    /// Everything is done (a new track, releasing all, quitting): `.useGlobal` to send if anything held it.
    mutating func releaseAll() -> Change? {
        guard isHeld else { return nil }
        reasons.removeAll()
        return .useGlobal
    }
}

extension Bridge {
    /// Turns this deck's quantize off for `reason`, if nothing else already has (#366).
    func overrideQuantize(_ reason: QuantizeOverride.Reason) {
        if let change = quantizeOverride.acquire(reason) { sendDeck("Quantize", .int(change.value)) }
    }

    /// `reason` is done; the last one out puts quantize back to Use Global.
    func restoreQuantize(_ reason: QuantizeOverride.Reason) {
        if let change = quantizeOverride.release(reason) { sendDeck("Quantize", .int(change.value)) }
    }

    /// Every reason is done (releasing everything, a new track): quantize back, once, if anything held it.
    func restoreAllQuantize() {
        if let change = quantizeOverride.releaseAll() { sendDeck("Quantize", .int(change.value)) }
    }
}
