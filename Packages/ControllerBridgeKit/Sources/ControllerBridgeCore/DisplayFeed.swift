// The display feed (#490, #616): the deck in front, as plain OSC, for a display other than the jog display, such as
// the panel. One value per address under one prefix; only changes go out, and a full snapshot when the deck in front
// changes, when the feed is turned on and when its address changes. It only sends (ADR 0011).

final class DisplayFeed {
    /// Every address starts with this.
    static let prefix = "/DeckBridge/Display/"

    /// What the feed shows of the deck in front.
    struct Deck: Equatable {
        /// Syndicate's deck number, 1-4.
        var number: Int
        /// The deck color in use, [r, g, b] 0-255: the ring's and the app badge's.
        var color: [Int]
        /// A track is loaded. False is the empty state: every other field empty.
        var loaded = false
        /// "" while the deck is empty.
        var title = ""
        var artist = ""

        /// The full snapshot, in the feed's order. #617 adds its fields here.
        var messages: [OSCMessage] {
            let rgb = color.count == 3 ? color.map { Int32(max(0, min(255, $0))) } : [255, 255, 255]
            return [
                OSCMessage(DisplayFeed.prefix + "deck", [.int(Int32(number))]),
                OSCMessage(DisplayFeed.prefix + "color", [.int(rgb[0] << 16 | rgb[1] << 8 | rgb[2])]),
                OSCMessage(DisplayFeed.prefix + "loaded", [.int(loaded ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "title", [.string(title)]),
                OSCMessage(DisplayFeed.prefix + "artist", [.string(artist)]),
            ]
        }
    }

    private var sender: (any OSCSender)?
    private var settings = DisplayFeedSettings()
    /// What each address carried last, as sent; empty means the next update is a full snapshot.
    private var sent: [String: [OSCArgument]] = [:]
    /// The deck number the last update was for: another deck in front is a full snapshot.
    private var sentDeck: Int?

    /// Where the feed's OSC goes. The app's sender is the display's own UDP destination, off the event path.
    func attach(_ sender: any OSCSender) {
        self.sender = sender
        sent = [:]
    }

    /// The setting. Turning it on, or a new host or port, makes the next update a full snapshot.
    func set(_ new: DisplayFeedSettings) {
        if new.enabled && (!settings.enabled || new.host != settings.host || new.port != settings.port) { sent = [:] }
        settings = new
    }

    /// The next update is a full snapshot.
    func resend() {
        sent = [:]
    }

    /// Sends what changed about the deck in front: everything when it's another deck.
    func update(_ deck: Deck?) {
        guard settings.enabled, let sender, let deck else { return }
        if deck.number != sentDeck { sent = [:] }
        sentDeck = deck.number
        for message in deck.messages where sent[message.address] != message.arguments {
            sender.send(message)
            sent[message.address] = message.arguments
        }
    }
}
