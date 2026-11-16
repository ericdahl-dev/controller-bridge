/// One controller's translation: its MIDI in to Syndicate OSC, and Syndicate feedback to its LEDs.
///
/// Controls are added in extensions (one file per group), each registering its buttons in `buttonHandlers`.
final class Bridge {
    static let full: UInt8 = 127
    static let dim: UInt8 = 1
    static let off: UInt8 = 0

    /// Button handlers by mapping note name. Each is called with `pressed` on every press and release.
    static var buttonHandlers: [String: (Bridge) -> (Bool) -> Void] {
        [
            "play": { $0.play },
            "cue": { $0.cue },
            "censor": { $0.censor },
            "sync": { $0.sync },
            "master": { $0.master },
            "pitch_minus": { $0.pitchMinus },
            "pitch_plus": { $0.pitchPlus },
            "shift": { $0.shiftButton },
            "key_lock": { $0.keyLock },
            "slip": { $0.slip },
            // Pad modes (Bridge+Pads.swift).
            "mode_hotcue": { $0.padModeButton(.hotCue) },
            "mode_roll": { $0.padModeButton(.roll) },
            "mode_loop": { $0.padModeButton(.loop) },
            "mode_slicer": { $0.padModeButton(.slicer) },
            "platter_touch": { $0.platterTouch },
            // Browse, loops and jumps (Bridge+Browse.swift).
            "track_prev": { $0.trackPrevious },
            "track_next": { $0.trackNext },
            "back": { $0.browserBack },
            "forward": { $0.browserForward },
            "select_press": { $0.selectPress },
            "loop_in": { $0.loopIn },
            "loop_out": { $0.loopOut },
            "auto_loop": { $0.autoLoop },
            "beat_jump_back": { $0.beatJumpBack },
            "beat_jump_forward": { $0.beatJumpForward },
            "param_back": { $0.paramBack },
            "param_forward": { $0.paramForward },
        ]
    }

    /// CC handlers by name (see `ccNames`). Each is called with the raw 0-127 value.
    static var ccHandlers: [String: (Bridge) -> (UInt8) -> Void] {
        [
            // Browse, loops and jumps (Bridge+Browse.swift).
            "select_turn": { $0.selectTurn },
            "auto_loop_size": { $0.autoLoopSize },
            // Pitch, jog and Needle Drop (Bridge+Continuous.swift).
            "pitch_msb": { $0.pitchMSB },
            "pitch_lsb": { $0.pitchLSB },
            "jog_msb": { $0.jogMSB },
            "jog_lsb": { $0.jogLSB },
            "needle_msb": { $0.needleMSB },
            "needle_lsb": { $0.needleLSB },
        ]
    }

    var mapping: Mapping
    var output: (any MIDIOutput)? {
        didSet { outputFailed = false }
    }
    /// A send to `output` failed since it was opened.
    private(set) var outputFailed = false
    private let osc: any OSCSender
    let clock: any Clock
    private let root: String
    /// The mapping's MIDI channel, 0-based.
    let channel: UInt8
    /// Button names by note, from the mapping.
    private let buttonNames: [Int: String]
    /// CC names by number: "jog", "pitch_msb", "pitch_lsb", "needle", "select_turn" and "auto_loop_size".
    private let ccNames: [Int: String]

    // Controller state.
    var shift = false
    var padMode = PadMode.hotCue
    var held = HeldControls()
    var keyLockOn = false
    /// The deck colors the ring shows (#122); a setting can replace the defaults (#123).
    var deckColors = DeckColors.defaults
    /// The address of a Reverse latched on with Shift + Censor (#114), so release-all turns it off on that deck.
    var latchedReverse: String?
    /// Lines for the log, taken by the Coordinator after each event (#114).
    var notices: [String] = []
    /// The pitch-range notice was logged already.
    var pitchRangeNoted = false
    var slipOn = false

    // Pitch, jog and Needle Drop state (Bridge+Continuous.swift).
    var pitchMSBValue: UInt8 = 0
    var pitchLSBValue: UInt8 = 0
    /// The last TempoSlider value sent, so a repeat isn't resent.
    var lastTempo: Double?
    /// Pitch pickup (#22): while armed, the fader is ignored until it meets Syndicate's reported TempoSlider.
    var pickupArmed = false
    var reportedTempo: Double?
    /// After a deck switch, the new deck's tempo isn't known yet: until this time the fader waits for Syndicate's
    /// report instead of jumping the new deck (#62). Nil when not waiting.
    var tempoWaitUntil: Double?
    /// Where the fader was on its last move while armed, to see it cross the reported value.
    var faderPosition: Double?
    /// TempoSlider values sent lately, with when, so a late echo of one isn't taken for an outside change.
    var recentTempoSends: [(time: Double, value: Double)] = []
    /// The direction of the PhaseBend being held (1 or -1), or 0 when none is.
    var bendDirection = 0
    var lastJogTime = 0.0
    var platterTouched = false
    var needleTouched = false
    /// Where the playhead is, 0...1, and the track's length in seconds, from feedback.
    var progress: Double?
    var duration: Double?
    /// Paused jog ticks not yet worth a whole beat.
    var seekCountRemainder = 0
    /// The jog's and the Needle Drop's last MSB, and the platter's last position, for 14-bit pairs (#103).
    var jogMSBValue: UInt8 = 0
    var jogPosition: Int?
    var needleMSBValue: UInt8 = 0

    // Syndicate's state, from feedback.
    var playing = false
    /// A quantized start is waiting for the beat.
    var playPending = false
    /// When the last pulsed beat of Syndicate's master clock arrived, if any.
    var lastPulseTime: Double?
    /// When any master clock beat last arrived, pulsed or not.
    var lastClockTime: Double?
    var loaded = false
    var synced = false
    var sliderEnabled = true
    var looping = false
    /// Syndicate's feedback has stopped (#21): its LEDs show `leds.stale_idle`.
    var feedbackStale = false
    /// An LED sweep (#26) owns the controller's LEDs.
    var ledsHeld = false
    /// Each hot cue's color slot, 0 for an empty cue.
    var cues = [Int](repeating: 0, count: 8)
    /// Cue colors by slot, Syndicate's defaults until ColorPalette feedback arrives.
    var palette = Bridge.defaultPalette

    /// The last velocity sent to each LED note, so an unchanged LED is never sent twice.
    private var ledCache: [Int: UInt8] = [:]
    /// Settings' LEDs switch (#19). While off, nothing is sent to the controller's LEDs.
    private(set) var ledsEnabled = true

    init(mapping: Mapping, osc: any OSCSender, clock: any Clock) {
        self.mapping = mapping
        self.osc = osc
        self.clock = clock
        root = "/" + mapping.osc.root.trimmingSlashes() + "/"
        // A loaded mapping's channel is checked to be 1-16; clamping keeps a hand-built one from trapping.
        channel = UInt8(clamping: mapping.midi.channel - 1)
        buttonNames = Dictionary(mapping.notes.buttons.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var ccNames: [Int: String] = [:]
        ccNames[mapping.jog.msbCC] = "jog_msb"
        ccNames[mapping.jog.lsbCC] = "jog_lsb"
        ccNames[mapping.pitch.msbCC] = "pitch_msb"
        ccNames[mapping.pitch.lsbCC] = "pitch_lsb"
        ccNames[mapping.needle.msbCC] = "needle_msb"
        ccNames[mapping.needle.lsbCC] = "needle_lsb"
        ccNames[mapping.browse.selectTurnCC] = "select_turn"
        ccNames[mapping.browse.autoLoopSizeCC] = "auto_loop_size"
        self.ccNames = ccNames
    }

    /// The resync for this controller: forget what the LEDs show and repaint every one. The Coordinator asks
    /// Syndicate to resend (one Resend for all controllers, #21).
    /// The controller switched to this deck layer (#79): it shows this layer's LEDs now, so paint them all. The one
    /// pitch fader is shared by every layer, so its position belongs to another deck now: wait for pickup again.
    func becameActiveLayer() {
        layerShown = true
        rearmPickup()
        ledCache.removeAll()
        refreshLEDs()
    }

    func start() {
        feedbackStale = false
        rearmPickup()
        ledCache.removeAll()
        refreshLEDs()
    }

    // MARK: MIDI in

    func handle(_ event: MIDIEvent) {
        switch event {
        case .noteOn(let channel, let note, let velocity) where channel == self.channel:
            handleNote(Int(note), pressed: velocity > 0)
        case .noteOff(let channel, let note, _) where channel == self.channel:
            handleNote(Int(note), pressed: false)
        case .controlChange(let channel, let controller, let value) where channel == self.channel:
            handleCC(Int(controller), value: value)
        default:
            break
        }
    }

    private func handleNote(_ note: Int, pressed: Bool) {
        if let pad = mapping.notes.pads.firstIndex(of: note) { return handlePad(pad, pressed: pressed) }
        if note == mapping.needle.touchNote {
            needleTouched = pressed
            return
        }
        guard let name = buttonNames[note], let handler = Self.buttonHandlers[name] else { return }
        handler(self)(pressed)
    }

    private func handleCC(_ controller: Int, value: UInt8) {
        guard let name = ccNames[controller], let handler = Self.ccHandlers[name] else { return }
        handler(self)(value)
    }

    // MARK: Feedback in

    func handle(_ message: OSCMessage) {
        // Syndicate matches addresses without regard to case, so feedback is read the same way.
        let address = message.address.lowercased()
        // Cue colors are for every deck, so they come before the deck check.
        if address == (root + "ColorPalette").lowercased() { return colorPalette(message.arguments) }
        // The master clock is one for all decks too.
        if address == (root + "Header/Clock").lowercased() { return headerClock(message.arguments) }
        let deckPrefix = (root + "Deck/\(mapping.deck.number)/").lowercased()
        guard address.hasPrefix(deckPrefix) else { return }
        let key = address.dropFirst(deckPrefix.count)
        let value = message.arguments.first?.isTrue ?? false
        switch key {
        case "playing":
            playing = value
            if !playing, bendDirection != 0 { endBend() }
        case "playpending": playPending = value
        case "temposlider":
            guard let reported = message.arguments.first?.number else { return }
            tempoReported(reported)
        case "loaded":
            loaded = value
            if loaded { rearmPickup() }
            if !loaded {
                // The track is gone: forget its cues, where it was and how long it was.
                cues = [Int](repeating: 0, count: 8)
                progress = nil
                duration = nil
            }
        case "sync": synced = value
        case "temposliderenabled":
            if value != sliderEnabled { rearmPickup() }
            sliderEnabled = value
        case "loop": looping = value
        case "cues": cues = Self.cueSlots(message.arguments)
        case "trackinfo":
            // Title, artist, key, BPM, length in seconds, …: only the length is used, for jog seeking.
            guard message.arguments.count >= 5 else { return }
            let length = message.arguments[4].number ?? 0
            duration = length > 0 ? length : nil
            return
        case "progress":
            progress = message.arguments.first?.number
            return
        default: return
        }
        refreshLEDs()
    }

    // MARK: LEDs

    func refreshLEDs() {
        playLED()
        refreshTransportLEDs()
        loopLEDs()
        padLEDs()
        led(mapping.leds.pitchCenter, pitchCenterVelocity)
    }

    func buttonLED(_ name: String, on: Bool) {
        guard let note = mapping.notes.buttons[name] else { return }
        var idle = mapping.leds.dimUnlitButtons ? Self.dim : Self.off
        if feedbackStale, Self.syndicateButtons.contains(name), mapping.leds.staleIdle == .off { idle = Self.off }
        led(note, on ? Self.full : idle)
    }

    /// An LED write for the LED sweep (#26): straight to the controller, past the cache.
    func sweepLED(_ note: Int, _ velocity: UInt8) {
        guard let output else { return }
        do { try output.send(.noteOn(channel: channel, note: UInt8(note), velocity: velocity)) } catch { outputFailed = true }
    }

    /// Clears the LED cache and repaints every LED from the current state, as after an LED sweep.
    func repaintLEDs() {
        ledCache.removeAll()
        refreshLEDs()
    }


    /// Turns the LEDs off (each lit one once, then nothing more) or back on (a full repaint).
    func setLEDsEnabled(_ enabled: Bool) {
        guard enabled != ledsEnabled else { return }
        if enabled {
            ledsEnabled = true
            ledCache.removeAll()
            refreshLEDs()
        } else {
            for (note, velocity) in ledCache.sorted(by: { $0.key < $1.key }) where velocity != Self.off { led(note, Self.off) }
            ledsEnabled = false
        }
    }

    /// This bridge is a deck layer the controller is showing (#79). A hidden layer keeps its state and repaints when
    /// it comes to the front.
    var layerShown = true
    /// The channel this layer's LEDs go out on, if not its own (#79): ch1 (0) while the controller sends every
    /// control on ch1 and only signals the layer.
    var ledChannel: UInt8?

    func led(_ note: Int, _ velocity: UInt8) {
        // During an LED sweep (#26) the bridge's own writes wait; the sweep ends with a repaint.
        // A deck layer the controller isn't showing writes nothing: the unit shows one layer at a time (#79).
        guard !ledsHeld, ledsEnabled, layerShown, ledCache[note] != velocity else { return }
        ledCache[note] = velocity
        guard let output else { return }
        do {
            try output.send(.noteOn(channel: ledChannel ?? channel, note: UInt8(note), velocity: velocity))
        } catch {
            // The Coordinator treats this as an unplug once the current event is handled.
            outputFailed = true
        }
    }

    // MARK: OSC out

    /// The full address of a path on this Bridge's deck, such as `/Syndicate/Deck/1/PlayPause`.
    func deckAddress(_ path: String) -> String {
        root + "Deck/\(mapping.deck.number)/" + path
    }

    func sendDeck(_ path: String, _ arguments: OSCArgument...) {
        osc.send(OSCMessage(deckAddress(path), arguments))
    }

    func send(_ path: String, _ arguments: OSCArgument...) {
        osc.send(OSCMessage(root + path, arguments))
    }

    /// Sends a message to a full address, such as a recorded release.
    func send(address: String, _ arguments: [OSCArgument]) {
        osc.send(OSCMessage(address, arguments))
    }
}

private extension OSCArgument {
    /// Feedback flags arrive as an int or a float; anything nonzero is on.
    var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .float(let value): Double(value)
        case .string: nil
        }
    }

    var isTrue: Bool {
        switch self {
        case .int(let value): value != 0
        case .float(let value): value != 0
        case .string: false
        }
    }
}

private extension String {
    func trimmingSlashes() -> String {
        String(drop { $0 == "/" }.reversed().drop { $0 == "/" }.reversed())
    }
}
