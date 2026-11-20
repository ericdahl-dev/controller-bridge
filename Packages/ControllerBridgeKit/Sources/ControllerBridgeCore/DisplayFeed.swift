// The display feed (#490, #616): the deck in front, as plain OSC, for a display other than the jog display, such as
// the panel. One value per address under one prefix; only changes go out, and a full snapshot when the deck in front
// changes and each time the destination opens (turned on, a new address, a wake). It only sends (ADR 0011).

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
        /// In Settings' key notation, as the jog display writes it.
        var key = ""
        /// The live BPM, else the track's; 0 unknown.
        var bpm = 0.0
        /// The change from the track's BPM, in percent; 0 when the track's is unknown.
        var tempo = 0.0
        var playing = false
        /// The deck's CUE button is held.
        var cue = false
        var sync = false
        /// Syndicate's tempo master: synced, with its tempo slider enabled, as the Master LED shows it.
        var master = false
        var loop = false
        /// The loop's length in beats, fractions too; 0 with no loop.
        var loopLength = 0.0
        /// Syndicate's master clock beat, 1-4, the same on every deck; 0 for none.
        var beat = 0
        /// The track time in whole seconds, as the drawn display counts it; remaining is 0 with no known length.
        var elapsed = 0
        var remaining = 0
        /// Through the track, 0-1.
        var progress = 0.0
        /// Against the master, 0-1, 0.5 in phase; -1 unknown (stopped, or no offset yet).
        var phase = -1.0

        /// The full snapshot, in the feed's order. #617 adds its fields here.
        var messages: [OSCMessage] {
            let rgb = color.count == 3 ? color.map { Int32(max(0, min(255, $0))) } : [255, 255, 255]
            return [
                OSCMessage(DisplayFeed.prefix + "deck", [.int(Int32(number))]),
                OSCMessage(DisplayFeed.prefix + "color", [.int(rgb[0] << 16 | rgb[1] << 8 | rgb[2])]),
                OSCMessage(DisplayFeed.prefix + "loaded", [.int(loaded ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "title", [.string(title)]),
                OSCMessage(DisplayFeed.prefix + "artist", [.string(artist)]),
                OSCMessage(DisplayFeed.prefix + "key", [.string(key)]),
                OSCMessage(DisplayFeed.prefix + "bpm", [.float(Float(bpm))]),
                OSCMessage(DisplayFeed.prefix + "tempo", [.float(Float(tempo))]),
                OSCMessage(DisplayFeed.prefix + "playing", [.int(playing ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "cue", [.int(cue ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "sync", [.int(sync ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "master", [.int(master ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "loop", [.int(loop ? 1 : 0)]),
                OSCMessage(DisplayFeed.prefix + "loopLength", [.float(Float(loopLength))]),
                OSCMessage(DisplayFeed.prefix + "beat", [.int(Int32(beat))]),
                OSCMessage(DisplayFeed.prefix + "elapsed", [.int(Int32(elapsed))]),
                OSCMessage(DisplayFeed.prefix + "remaining", [.int(Int32(remaining))]),
                OSCMessage(DisplayFeed.prefix + "progress", [.float(Float(progress))]),
                OSCMessage(DisplayFeed.prefix + "phase", [.float(Float(phase))]),
            ]
        }
    }

    private var sender: (any OSCSender)?
    private var settings = DisplayFeedSettings()
    /// The destination is open at the setting's address: turning the feed on or a new address waits for it, since
    /// until then a send would be dropped or reach the old address. The one snapshot goes when it opens (#617).
    private var open = false
    /// Once the destination opens, the first snapshot waits until Syndicate's answer makes the deck known, at most
    /// until this time, so a panel never flashes a default color or an empty deck at launch (#617).
    private var holdUntil: Double?
    static let holdSeconds = 1.0
    /// The fast fields go out at most once per `fastInterval` each (#617): a change inside it waits, and the next
    /// update after it sends the value then, so the latest wins and nothing queues. A snapshot sends them at once.
    static let fastAddresses: Set<String> = [prefix + "progress", prefix + "phase"]
    static let fastInterval = 1.0 / 30
    /// When each fast field may next go out: a slot every `fastInterval`, kept on its cadence so updates that land
    /// between slots still average about 30 a second, never bursting to catch up.
    private var fastDue: [String: Double] = [:]
    /// What each address carried last, as sent; empty means the next update is a full snapshot.
    private var sent: [String: [OSCArgument]] = [:]
    /// The deck number the last update was for: another deck in front is a full snapshot.
    private var sentDeck: Int?

    /// Where the feed's OSC goes. The app's sender is the display's own UDP destination, off the event path.
    func attach(_ sender: any OSCSender) {
        self.sender = sender
        sent = [:]
    }

    /// The setting. Turning it on, or a new host or port, waits for the destination to open.
    func set(_ new: DisplayFeedSettings) {
        if new.enabled && (!settings.enabled || new.host != settings.host || new.port != settings.port) {
            sent = [:]
            open = false
        }
        settings = new
    }

    /// Turned on with somewhere to send: worth building the deck for.
    var on: Bool { settings.enabled && sender != nil }

    /// The destination opened (or opened again, after a wake) at `now`: the next update is a full snapshot.
    func resend(at now: Double) {
        sent = [:]
        open = true
        holdUntil = now + Self.holdSeconds
    }

    /// Sends what changed about the deck in front: everything when it's another deck. `known`: Syndicate has
    /// answered for it (its color and its deck), which ends the hold on the first snapshot.
    func update(_ deck: Deck?, known: Bool = true, at now: Double = 0) {
        guard settings.enabled, open, let sender, let deck else { return }
        if let until = holdUntil {
            guard known || now >= until else { return }
            holdUntil = nil
        }
        if deck.number != sentDeck { sent = [:] }
        sentDeck = deck.number
        let snapshot = sent.isEmpty
        for message in deck.messages where sent[message.address] != message.arguments {
            if Self.fastAddresses.contains(message.address) {
                let due = fastDue[message.address]
                // A hair of slack, so an update on the slot isn't lost to rounding.
                if !snapshot, let due, now < due - 1e-9 { continue }
                fastDue[message.address] = (due.map { max($0, now - Self.fastInterval) } ?? now) + Self.fastInterval
            }
            sender.send(message)
            sent[message.address] = message.arguments
        }
    }
}
