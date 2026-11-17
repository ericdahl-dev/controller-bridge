/// One controller's translation: its MIDI in to Syndicate OSC, and Syndicate feedback to its LEDs.
///
/// Controls are added in extensions (one file per group), each registering its buttons in `buttonHandlers`.
final class Bridge {
    /// A pad or the ring with no color. Button LEDs take the profile's levels instead (#194).
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
            "mode_cycle": { $0.padModeCycle },
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
            "jog_relative": { $0.jogRelative },
            "jog_relative_edge": { $0.jogRelativeEdge },
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
    let root: String
    /// The mapping's MIDI channel, 0-based.
    let channel: UInt8
    /// Button names by note, from the mapping.
    private let buttonNames: [Int: String]
    /// Shift done in hardware (#226): each shifted note's button.
    private let shiftedNames: [Int: String]
    /// CC names by number: "jog", "pitch_msb", "pitch_lsb", "needle", "select_turn" and "auto_loop_size".
    private let ccNames: [Int: String]

    // Controller state.
    var shift = false
    var padMode = PadMode.hotCue
    var held = HeldControls()
    var keyLockOn = false
    /// The deck colors the ring shows (#122); a setting can replace the defaults (#123).
    var deckColors = DeckColors.defaults
    /// Vivid or exact ring and held-pad colors (#151).
    var ringColors = RingColors.vivid
    /// The address of a Reverse latched on with Shift + Censor (#114), so release-all turns it off on that deck.
    var latchedReverse: String?
    /// Lines for the log, taken by the Coordinator after each event (#114).
    var notices: [String] = []
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
    /// When the jog or needle strip last seeked a paused deck (#366).
    var lastSeekTime = 0.0
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
    /// The loaded track's TrackInfo, for the jog display (#165): nil when nothing is loaded.
    var track: (title: String, artist: String, key: String, bpm: Double, playerType: String)?
    /// The deck's live tempo from Syndicate's BPM feedback, for the jog needle's run between BarRamps (#165).
    var bpm: Double?
    var needleMSBValue: UInt8 = 0

    // Syndicate's state, from feedback.
    var playing = false
    /// A quantized start is waiting for the beat.
    var playPending = false
    /// Shift + hot cue pad on a stopped deck (#358): the cue tapped, and when, waiting for Syndicate's Playing 1 to
    /// pause it, with the deck's quantize forced to None until then (#363). Syndicate has no jump-without-play input,
    /// and a pause sent before the launch cancels the jump.
    var pendingCuePause: (cue: Int, armedAt: Double)?
    /// Who needs this deck's quantize off right now (#366): the cue jump, the paused jog's seeks, return to cue.
    var quantizeOverride = QuantizeOverride()
    /// Where each hot cue sits, in seconds, learned from a Shift + pad launch (#358): Syndicate never sends cue times.
    var cueTimes: [Int: Double] = [:]
    /// The cue just launched by Shift + pad, whose time the next Position gives.
    var learningCue: Int?
    /// The main CUE (#360): held, pressed with Shift (handled by the bridge, not Syndicate), where the deck last was,
    /// where the cue point is (Syndicate never reports it), and until when a stop after CUE-while-playing gives it.
    var cueDown = false
    var shiftCueDown = false
    var lastPosition: Double?
    var mainCue: Double?
    var mainCueSettlesUntil: Double?
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
    /// The mixer section's state (#207): pair halves, what was sent, what Syndicate reported, and the meter.
    var mixerState = MixerState()
    /// The capture window is recording this controller (#186, #187): its LEDs are the LED test's, so the bridge paints
    /// none until the capture ends and it repaints.
    var ledsCaptured = false
    /// Each hot cue's color slot, 0 for an empty cue.
    lazy var cues = [Int](repeating: 0, count: mapping.notes.pads.count)
    /// Cue colors by slot, Syndicate's defaults until ColorPalette feedback arrives.
    var palette = Bridge.defaultPalette

    /// The last velocity sent to each LED note, so an unchanged LED is never sent twice.
    private var ledCache: [Int: UInt8] = [:]
    /// The same for pad LEDs on the pads' own channel (#224), kept apart: a pad's note can be a button's on another
    /// channel.
    private var padLEDCache: [Int: UInt8] = [:]
    /// The pads' MIDI channel, 0-15 (#224): the deck's unless the profile gives the pads their own.
    let padChannel: UInt8
    /// The channel the pads send on with Shift held, 0-15 (#324), when the hardware does Shift itself; nil otherwise.
    let shiftedPadChannel: UInt8?
    /// Settings' LEDs switch (#19). While off, nothing is sent to the controller's LEDs.
    private(set) var ledsEnabled = true

    init(mapping: Mapping, osc: any OSCSender, clock: any Clock) {
        self.mapping = mapping
        self.osc = osc
        self.clock = clock
        root = "/" + mapping.osc.root.trimmingSlashes() + "/"
        // A loaded mapping's channel is checked to be 1-16; clamping keeps a hand-built one from trapping.
        channel = UInt8(clamping: mapping.midi.channel - 1)
        padChannel = UInt8(clamping: (mapping.pads.channel ?? mapping.midi.channel) - 1)
        shiftedPadChannel = mapping.pads.shiftedChannel.map { UInt8(clamping: $0 - 1) }
        buttonNames = Dictionary(mapping.notes.buttons.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        shiftedNames = Dictionary(mapping.notes.shifted.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var ccNames: [Int: String] = [:]
        switch mapping.jog?.mode {
        case .absolute(let msb, let lsb):
            ccNames[msb] = "jog_msb"
            ccNames[lsb] = "jog_lsb"
        case .relative(let cc, let edge):
            ccNames[cc] = "jog_relative"
            if let edge { ccNames[edge] = "jog_relative_edge" }
        case nil:
            // No jog wheel (#341): nothing to listen for.
            break
        }
        if let pitch = mapping.pitch { ccNames[pitch.msbCC] = "pitch_msb" }
        // A 7-bit fader has no LSB, even if a merged mapping still names one (#195).
        if let pitch = mapping.pitch, pitch.bits == 14, let lsb = pitch.lsbCC { ccNames[lsb] = "pitch_lsb" }
        if let needle = mapping.needle {
            ccNames[needle.msbCC] = "needle_msb"
            ccNames[needle.lsbCC] = "needle_lsb"
        }
        if let browse = mapping.browse {
            ccNames[browse.selectTurnCC] = "select_turn"
            ccNames[browse.autoLoopSizeCC] = "auto_loop_size"
        }
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
        padLEDCache.removeAll()
        refreshLEDs()
    }

    /// Paints from scratch. `stale` keeps the stale look, for a bridge that replaces one while feedback is stale (#134).
    func start(stale: Bool = false) {
        feedbackStale = stale
        rearmPickup()
        rearmMixer()
        ledCache.removeAll()
        padLEDCache.removeAll()
        mixerState.meterShown = nil   // shown again on the next tick, on what may be a new port (#320)
        refreshLEDs()
    }

    // MARK: MIDI in

    func handle(_ event: MIDIEvent) {
        // A pad on the shifted pad channel (#324) is that pad with Shift held, for that press or release only, as a
        // shifted note is (#226).
        if let shiftedPadChannel {
            let pad: (note: UInt8, pressed: Bool)? = switch event {
            case .noteOn(shiftedPadChannel, let note, let velocity): (note, velocity > 0)
            case .noteOff(shiftedPadChannel, let note, _): (note, false)
            default: nil
            }
            if let pad {
                let wasShifted = shift
                shift = true
                _ = padNote(Int(pad.note), pressed: pad.pressed)
                shift = wasShifted
                refreshLEDs()
                return
            }
        }
        // Pads on their own channel (#224) play only there; on the deck's channel they're handled with the other notes.
        // With their own channel, a deck-channel note is a button even when a pad has the same number (#322).
        if padChannel != channel {
            switch event {
            case .noteOn(padChannel, let note, let velocity):
                _ = padNote(Int(note), pressed: velocity > 0)
                return
            case .noteOff(padChannel, let note, _):
                _ = padNote(Int(note), pressed: false)
                return
            default:
                break
            }
        }
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
        if mixerNote(note, pressed: pressed) { return }
        if padChannel == channel, padNote(note, pressed: pressed) { return }
        if let needle = mapping.needle, note == needle.touchNote {
            needleTouched = pressed
            // The strip let go: its seeks are done (#366).
            if !pressed { restoreQuantize(.jogSeek) }
            return
        }
        // A shifted note (#226) is its button with Shift held, for that press or release only; Shift then goes back to
        // what it was (a handler may clear it, and the app's own Shift may be held).
        if let name = shiftedNames[note], let handler = Self.buttonHandlers[name] {
            let wasShifted = shift
            shift = true
            handler(self)(pressed)
            shift = wasShifted
            // A handler that repainted while Shift was set lit the Shift LED; paint it back (cached, so cheap).
            refreshLEDs()
            return
        }
        guard let name = buttonNames[note], let handler = Self.buttonHandlers[name] else { return }
        handler(self)(pressed)
    }

    private func handleCC(_ controller: Int, value: UInt8) {
        if mixerCC(controller, value: value) { return }
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
        // The mixer channel of this deck (#207).
        if mapping.mixer != nil, let mixer = MixerOSC.parse(message.address, root: root) {
            if mixer.channel == mapping.deck.number { mixerFeedback(mixer.value, message.arguments) }
            return
        }
        let deckPrefix = (root + "Deck/\(mapping.deck.number)/").lowercased()
        guard address.hasPrefix(deckPrefix) else { return }
        let key = address.dropFirst(deckPrefix.count)
        let value = message.arguments.first?.isTrue ?? false
        switch key {
        case "playing":
            playing = value
            if value { cueLaunched() }
            if !value { mainCueStopped() }
            if !playing, bendDirection != 0 { endBend() }
        case "playpending":
            playPending = value
        case "temposlider":
            guard let reported = message.arguments.first?.number else { return }
            tempoReported(reported)
        case "loaded":
            loaded = value
            if loaded { rearmPickup() }
            if !loaded {
                forgetCues()
                // The track is gone: forget its cues, where it was and how long it was.
                cues = [Int](repeating: 0, count: mapping.notes.pads.count)
                progress = nil
                duration = nil
                track = nil
            }
        case "sync": synced = value
        case "bpm": bpm = message.arguments.first?.number.flatMap { $0 > 0 ? $0 : nil }
        case "temposliderenabled":
            if value != sliderEnabled { rearmPickup() }
            sliderEnabled = value
        case "loop": looping = value
        case "cues": cues = Self.cueSlots(message.arguments, pads: mapping.notes.pads.count)
        case "trackinfo":
            // Title, artist, key, BPM, length in seconds, …: only the length is used, for jog seeking.
            guard message.arguments.count >= 5 else { return }
            let length = message.arguments[4].number ?? 0
            duration = length > 0 ? length : nil
            // <title> <artist> <key> <bpm> <length> <bars> <beats> <player_type> (the #165 capture): by argument,
            // never by splitting text, since titles and artists hold spaces and commas.
            func text(_ index: Int) -> String {
                if message.arguments.indices.contains(index), case .string(let value) = message.arguments[index] { return value }
                return ""
            }
            let previous = track
            track = (text(0), text(1), text(2), message.arguments[3].number ?? 0, text(7))
            // Another track: what Shift + pad learned was about the last one (#358). A Resend of the same keeps it.
            if previous?.title != text(0) || previous?.artist != text(1) { forgetCues() }
            return
        case "position":
            guard let seconds = message.arguments.first?.number else { return }
            if let cue = learningCue, playing { learnCue(cue, at: seconds) }
            positionReported(seconds)
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
        mixerLEDs()
    }

    /// A button LED's full, dim and off velocities, from the profile (#194).
    var fullLevel: UInt8 { UInt8(clamping: mapping.leds.levels.full) }
    var dimLevel: UInt8 { UInt8(clamping: mapping.leds.levels.dim) }
    var offLevel: UInt8 { UInt8(clamping: mapping.leds.levels.off) }

    func buttonLED(_ name: String, on: Bool) {
        guard let note = mapping.notes.buttons[name] else { return }
        var idle = mapping.leds.dimUnlitButtons ? dimLevel : offLevel
        if feedbackStale, Self.syndicateButtons.contains(name), mapping.leds.staleIdle == .off { idle = offLevel }
        led(note, on ? fullLevel : idle)
        // Its shifted note's LED (#226), when the profile mirrors it.
        if mapping.leds.mirrorShifted, let shifted = mapping.notes.shifted[name] { led(shifted, on ? fullLevel : idle) }
    }

    /// An LED write for the LED sweep (#26): straight to the controller, past the cache.
    func sweepLED(_ note: Int, _ velocity: UInt8) {
        guard let output else { return }
        // A pad's note goes to the pads' own channel (#224); the sweep only sends pad notes in its color pass.
        let onPads = mapping.pads.channel != nil && mapping.notes.pads.contains(note)
        do { try output.send(.noteOn(channel: onPads ? padChannel : channel, note: UInt8(note), velocity: velocity)) } catch {
            outputFailed = true
        }
    }

    /// Clears the LED cache and repaints every LED from the current state, as after an LED sweep.
    func repaintLEDs() {
        ledCache.removeAll()
        padLEDCache.removeAll()
        // The meter shows again on its next tick (#320).
        mixerState.meterShown = nil
        refreshLEDs()
    }


    /// Turns the LEDs off (each lit one once, then nothing more) or back on (a full repaint).
    func setLEDsEnabled(_ enabled: Bool) {
        guard enabled != ledsEnabled else { return }
        if enabled {
            ledsEnabled = true
            ledCache.removeAll()
            padLEDCache.removeAll()
            mixerState.meterShown = nil
            refreshLEDs()
        } else {
            // A button goes to the profile's off (#194); a pad or the ring to no color.
            let colorNotes = Set(mapping.notes.pads + [mapping.leds.ring] + [PadMode.hotCue, .roll, .loop, .slicer].flatMap(padNotes))
            for (note, velocity) in ledCache.sorted(by: { $0.key < $1.key }) {
                let off = colorNotes.contains(note) ? Self.off : offLevel
                if velocity != off { led(note, off) }
            }
            for (note, velocity) in padLEDCache.sorted(by: { $0.key < $1.key }) where velocity != Self.off {
                padLED(note, Self.off)
            }
            // The VU meter too (#320).
            if let meter = mapping.mixer?.meter, let shown = mixerState.meterShown, shown != 0, ledCC(UInt8(meter.cc), 0) {
                mixerState.meterShown = nil
            }
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
        guard !ledsHeld, !ledsCaptured, ledsEnabled, layerShown, ledCache[note] != velocity else { return }
        ledCache[note] = velocity
        guard let output else { return }
        do {
            try output.send(.noteOn(channel: ledChannel ?? channel, note: UInt8(note), velocity: velocity))
        } catch {
            // The Coordinator treats this as an unplug once the current event is handled.
            outputFailed = true
        }
    }

    /// An LED driven by a CC, such as a VU meter (#207): straight out, as the caller limits how often. False when held,
    /// off or not shown, so nothing went out.
    func ledCC(_ controller: UInt8, _ value: UInt8) -> Bool {
        guard !ledsHeld, !ledsCaptured, ledsEnabled, layerShown, let output else { return false }
        do { try output.send(.controlChange(channel: channel, controller: controller, value: value)) } catch { outputFailed = true }
        return true
    }

    /// A pad's LED (#224): on the pads' own channel when the profile gives one, else like any other LED.
    func padLED(_ note: Int, _ velocity: UInt8) {
        guard mapping.pads.channel != nil else { return led(note, velocity) }
        guard !ledsHeld, !ledsCaptured, ledsEnabled, layerShown, padLEDCache[note] != velocity else { return }
        padLEDCache[note] = velocity
        guard let output else { return }
        do { try output.send(.noteOn(channel: padChannel, note: UInt8(note), velocity: velocity)) } catch { outputFailed = true }
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

extension OSCArgument {
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
