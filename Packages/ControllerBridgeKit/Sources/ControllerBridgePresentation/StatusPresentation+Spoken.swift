/// What VoiceOver hears (#67): natural case and no glyphs. The views keep their uppercase look through
/// `.textCase(.uppercase)`; the spoken text is built here, so it's tested.
extension StatusLight {
    /// "Feedback: port 9096 in use". Our own all-caps labels are capitalized; a device's name is kept as named.
    public var spoken: String {
        "\(spokenLabel): \(word.lowercased())"
    }

    /// The bridge's own labels are capitalized; a device's name is kept as named.
    var spokenLabel: String {
        kind == .device ? label : label.prefix(1) + label.dropFirst().lowercased()
    }
}

extension StatusPresentation {
    /// The status bar for VoiceOver: every light (not just the parts that fit the bar), every controller's deck, then
    /// master. "Denon LC6000 PRIME: connected. Feedback: live. Deck 1. Tempo master."
    public var spokenLine: String {
        let decks = blocks.map { String($0.deck) }
        let deckText = decks.count == 1 ? "Deck \(decks[0])"
            : "Decks " + decks.dropLast().joined(separator: ", ") + " and " + decks.last!
        let sentences = lights.map(\.spoken) + [deckText] + (master == nil ? [] : ["Tempo master"])
        return sentences.joined(separator: ". ") + "."
    }
}
