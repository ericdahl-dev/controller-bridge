// The jog display controller (#384): which deck the LC6000's jog display shows, each deck's needle, and the driver
// behind JogDisplayPort, from plain values per controller entry. The Coordinator only forwards to it; it reads no
// Bridge internals, only each Bridge's DeckFacts (#383).

final class JogDisplayController {
    private let clock: any Clock
    /// Each entry's needle: its deck's own phase in the bar (#165).
    private var needles: [Int: JogMarker] = [:]
    /// What each entry's facts said last, to see a new BarRamp and a deck that stops.
    private var lastRamp: [Int: DeckFacts.BarRamp] = [:]
    private var lastPlaying: [Int: Bool] = [:]
    /// Syndicate's master tempo, for a deck whose own BPM isn't known yet.
    private(set) var masterBPM: Double?
    /// The LC6000's jog display, when the app found its WD port.
    private var driver: JogDisplayDriver?
    /// Settings' "Show the deck on the jog display" (ADR-0005): while off, nothing goes to the display's ports, not
    /// even the hello.
    private(set) var enabled = false
    /// The deck the preview follows with no controller connected (#221): the user's pick, 1-4; nil, the first loaded.
    private(set) var previewDeck: Int?
    /// When the next needle is due: a schedule 1/`markerRate` apart (#558), so a send that lands late on a tick doesn't
    /// push the next one back. After a stall it restarts from now, with no burst to catch up.
    private var nextMarkerDue: Double?
    /// At most this many marker updates a second.
    static let markerRate = 30.0
    /// Each mixer channel's meter from Syndicate (#461): the latest level, 0...1, and the peak held since `peakAt`.
    private var meters: [Int: (level: Double, peak: Double, peakAt: Double)] = [:]
    private var lastMeterSent: Double?
    /// The deck whose meter went out last: a switch sends the new one's at once.
    private var lastMeterDeck: Int?
    /// How long a peak holds above the level: the mixer LEDs' default (mixer.meter.hold_ms), as the LC6000 has none.
    static let peakHold = Double(ProfileKeys.fallback("mixer.meter.hold_ms") as Int) / 1000

    init(clock: any Clock) {
        self.clock = clock
    }

    /// Syndicate's header feedback: the master tempo (and, for the ring, the master beat).
    func feedback(_ message: OSCMessage) {
        let address = message.address.lowercased()
        // A mixer channel's meter (#461), for the drawn display's level meter.
        if let channel = (1...4).first(where: { address.hasSuffix("/mixer/ch\($0)/meter") }),
           let level = message.arguments.first?.number {
            let now = clock.now, old = meters[channel]
            let fresh = old.map { level >= $0.peak || now - $0.peakAt > Self.peakHold } ?? true
            meters[channel] = (level, fresh ? level : old!.peak, fresh ? now : old!.peakAt)
        }
        if address.hasSuffix("/header/bpm"), let bpm = message.arguments.first?.number, bpm > 0 { masterBPM = bpm }
        // The master clock is the lit ring segment, the same on every deck (the user's pick).
        if address.hasSuffix("/header/clock"), let beat = message.arguments.first?.wholeNumber, (1...4).contains(beat) {
            driver?.masterBeat(beat)
        }
    }

    /// The unit's display firmware (#425), kept for a driver attached later.
    private var displayFirmware = DisplayFirmware.denon
    func setDisplayFirmware(_ firmware: DisplayFirmware) {
        displayFirmware = firmware
        driver?.displayFirmware = firmware
    }

    /// Says goodbye, so the next refresh says hello again (#429).
    func disconnect() {
        driver?.disconnect()
    }

    /// Whether the driver has said hello to a unit.
    var connected: Bool { driver?.connected ?? false }

    /// Syndicate's feedback stopped or came back (#464).
    func setStale(_ stale: Bool) {
        driver?.setStale(stale)
    }

    /// Whether the unit draws the screen itself now (#461).
    var drawing: Bool { if case .customDrawn = driver?.found { true } else { false } }

    /// The display firmware found on the unit (#456).
    var found: DisplayFound? { driver?.found }

    /// Whether the display is taking images now (#422).
    var uploading: Bool { driver?.uploading ?? false }

    /// Drives the display from now on.
    func attach(_ driver: JogDisplayDriver) {
        self.driver = driver
        driver.displayFirmware = displayFirmware
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func setPreviewDeck(_ deck: Int?) {
        previewDeck = deck
    }

    /// A message from the display's WD port: the unit's answers to an upload.
    func reply(_ bytes: [UInt8]) {
        driver?.reply(bytes)
    }

    /// The display shows the deck in front; every deck is previewed for the simulator (#221). With none connected,
    /// nothing reaches a unit (goodbye), but the preview follows a deck from Syndicate. Off, or with no WD port to show
    /// on (#305), nothing reaches the unit either.
    func refresh(_ entries: [Entry], color: (Int) -> [Int]?) {
        guard let driver else { return }
        func content(_ index: Int) -> JogDisplayContent {
            let facts = entries[index].facts, track = facts.track
            return JogDisplayContent(deck: facts.deck, color: color(facts.deck) ?? [255, 255, 255], title: track?.title,
                                     artist: track?.artist, key: track?.key, bpm: track?.bpm, playerType: track?.playerType)
        }
        for index in entries.indices { driver.preview(content(index)) }
        guard let first = entries.indices.first(where: { entries[$0].connected }) else {
            driver.disconnect()
            guard let index = Self.front(entries, previewDeck: previewDeck) else { return }
            return driver.show(content(index))
        }
        let front = Self.front(entries, previewDeck: previewDeck) ?? first
        if enabled, driver.attached { driver.connect() } else { driver.disconnect() }
        driver.show(content(front))
        // Every other deck's images stay on the unit too (#424), so a switch to it needs no upload.
        guard driver.connected else { return }
        for index in entries.indices where index != front && entries[index].facts.deck != entries[front].facts.deck {
            driver.keep(content(index))
        }
    }

    /// The driver's timers, then the needles (every playing deck's for the simulator, the deck in front's to the unit,
    /// at most 30 a second) and the play light: 127 while playing, blinking every half-second while loaded and paused.
    func tick(_ entries: [Entry]) {
        guard let driver else { return }
        driver.tick()
        let front = Self.front(entries, previewDeck: previewDeck)
        let due = nextMarkerDue.map { clock.now >= $0 - 1e-9 } ?? true
        if due {
            for index in entries.indices where entries[index].facts.playing {
                let needle = needle(index, at: clock.now)
                driver.deckMarker(deck: entries[index].facts.deck, needle)
                if index == front { driver.marker(needle) }
            }
            let period = 1 / Self.markerRate
            let next = (nextMarkerDue ?? clock.now) + period
            nextMarkerDue = next > clock.now ? next : clock.now + period
        }
        // Every deck's play state for the simulator, from Syndicate's Playing (#317), not the blinking light below.
        for entry in entries { driver.deckPlaying(deck: entry.facts.deck, entry.facts.playing) }
        drawnPreviewTick(entries, driver: driver)
        guard let front else { return }
        let facts = entries[front].facts
        meterTick(deck: facts.deck, driver: driver)
        timeTick(facts, driver: driver)
        phaseTick(entries, front: front, driver: driver)
        driver.deckState(loaded: facts.loaded, playing: facts.playing, pending: facts.playPending, loop: facts.looping,
                         cue: facts.cueHeld)
        driver.playLight(facts.playing || (facts.loaded && Int((clock.now / 0.5).rounded(.down)) % 2 == 0))
    }

    /// The deck in front's meter to the drawn display, at most 30 times a second; the peak falls to the level once
    /// it has held. Nothing until its channel has reported.
    /// The time message (#460): at most 4 a second, so a scrub doesn't flood the wire; a change held back goes
    /// once the quarter second is up. Steady play changes it once a second, so a seek goes at once. A new deck in
    /// front isn't held: its time lands with its deck message.
    static let timeRate = 4.0
    private var lastTimeSent: Double?, lastTimeDeck: Int?
    private func timeTick(_ facts: DeckFacts, driver: JogDisplayDriver) {
        if facts.deck == lastTimeDeck, let sent = lastTimeSent, clock.now - sent < 1 / Self.timeRate - 1e-9 { return }
        lastTimeDeck = facts.deck
        if driver.time(.time(elapsed: facts.position, length: facts.duration)) { lastTimeSent = clock.now }
    }

    /// Each deck's phase value (#462), from its PhaseOffset with DrawnPhase's hysteresis and wrap guard, kept for every
    /// deck so a switch shows the new one's at once.
    private var phases: [Int: DrawnPhase] = [:]
    private var lastPhaseSent: Double?
    private var lastPhaseDeck: Int?

    /// The deck in front's phase to the drawn display, at most 30 times a second (Syndicate sends about 45 during a
    /// nudge); a held-back change goes once the interval is up, and a deck switch at once.
    private func phaseTick(_ entries: [Entry], front: Int, driver: JogDisplayDriver) {
        var value = DrawnPhase.unknown
        for (index, entry) in entries.enumerated() {
            let facts = entry.facts
            let deckValue = phases[facts.deck, default: DrawnPhase()].value(offset: facts.phaseOffset, playing: facts.playing)
            if index == front { value = deckValue }
        }
        let deck = entries[front].facts.deck
        if deck == lastPhaseDeck, let sent = lastPhaseSent, clock.now - sent < 1 / Self.markerRate - 1e-9 { return }
        lastPhaseDeck = deck
        if driver.phase(value) { lastPhaseSent = clock.now }
    }

    /// Every deck's drawn preview (#465): its flags, needle, meter, phase and time, as the unit would get them.
    private func drawnPreviewTick(_ entries: [Entry], driver: JogDisplayDriver) {
        for (index, entry) in entries.enumerated() {
            let facts = entry.facts
            var flags: DrawnDisplay.State = []
            for (flag, on) in [(DrawnDisplay.State.loaded, facts.loaded), (.playing, facts.playing),
                               (.playPending, facts.playPending), (.loopOn, facts.looping), (.cueHeld, facts.cueHeld)] where on {
                flags.insert(flag)
            }
            func scaled(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 127).rounded()) }
            let meter = meters[facts.deck].map { (level: scaled($0.level), peak: scaled($0.peak)) }
            driver.drawnPreview(deck: facts.deck, flags: flags, needle: needle(index, at: clock.now), meter: meter,
                                phase: phases[facts.deck]?.lastValue ?? DrawnPhase.unknown,
                                time: .time(elapsed: facts.position, length: facts.duration))
        }
    }

    private func meterTick(deck: Int, driver: JogDisplayDriver) {
        // A channel that hasn't reported shows an empty meter, not the last deck's (#461).
        guard var meter = meters[deck] else {
            lastMeterDeck = deck
            driver.meter(level: 0, peak: 0)
            return
        }
        if deck == lastMeterDeck, let sent = lastMeterSent, clock.now - sent < 1 / Self.markerRate - 1e-9 { return }
        lastMeterDeck = deck
        if clock.now - meter.peakAt > Self.peakHold {
            meter.peak = meter.level
            meter.peakAt = clock.now
            meters[deck] = meter
        }
        func scaled(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 127).rounded()) }
        if driver.meter(level: scaled(meter.level), peak: scaled(meter.peak)) { lastMeterSent = clock.now }
    }

    /// Each entry's facts, after Syndicate's feedback: a deck that stops keeps its needle where it is, and a new
    /// BarRamp sets it, running on at the deck's tempo while it plays (the platter never moves it, #388).
    func observe(_ entries: [Entry]) {
        for (index, entry) in entries.enumerated() {
            let facts = entry.facts
            if lastPlaying[index] == true, !facts.playing { needles[index]?.freeze(at: clock.now) }
            lastPlaying[index] = facts.playing
            if let ramp = facts.barRamp, ramp != lastRamp[index] {
                lastRamp[index] = ramp
                let bpm = facts.playing ? facts.bpm ?? masterBPM ?? 120 : 0
                needles[index, default: JogMarker()].ramp(ramp.phase, bpm: bpm, at: ramp.at)
            }
        }
    }

    /// An entry's needle as pitch bend at `time`.
    func needle(_ index: Int, at time: Double) -> Int {
        (needles[index] ?? JogMarker()).pitchBend(at: time)
    }

    /// What the controller knows of one controller entry, in the Coordinator's order.
    struct Entry: Equatable {
        /// The entry's MIDI input is open.
        var connected: Bool
        /// Its profile excludes a WD port that's present: the display is its (#305).
        var ownsDisplay: Bool
        /// It's the active layer of its controller.
        var activeLayer: Bool
        var facts: DeckFacts
    }

    /// The entry whose deck the display shows. Connected: an entry that owns the display comes first, then the active
    /// layer, else the first. With none connected, the preview's (#221): the picked deck's, else the first loaded one's,
    /// else the first.
    static func front(_ entries: [Entry], previewDeck: Int?) -> Int? {
        let connected = entries.indices.filter { entries[$0].connected }
        if !connected.isEmpty {
            let owners = connected.filter { entries[$0].ownsDisplay }
            let candidates = owners.isEmpty ? connected : owners
            return candidates.first { entries[$0].activeLayer } ?? candidates.first
        }
        if let pick = previewDeck, let index = entries.indices.first(where: { entries[$0].facts.deck == pick }) { return index }
        return entries.indices.first { entries[$0].facts.loaded } ?? entries.indices.first
    }
}
