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
        ]
    }

    let mapping: Mapping
    var output: (any MIDIOutput)?
    private let osc: any OSCSender
    private let root: String
    /// The mapping's MIDI channel, 0-based.
    let channel: UInt8
    /// Button names by note, from the mapping.
    private let buttonNames: [Int: String]
    /// CC names by number: "jog", "pitch_msb", "pitch_lsb", "needle", "select_turn" and "auto_loop_size".
    private let ccNames: [Int: String]

    // Controller state.
    var shift = false
    var held = HeldControls()
    var keyLockOn = false
    var slipOn = false

    // Syndicate's state, from feedback.
    var playing = false
    var loaded = false
    var synced = false
    var sliderEnabled = true
    var looping = false

    /// The last velocity sent to each LED note, so an unchanged LED is never sent twice.
    private var ledCache: [Int: UInt8] = [:]

    init(mapping: Mapping, osc: any OSCSender) {
        self.mapping = mapping
        self.osc = osc
        root = "/" + mapping.osc.root.trimmingSlashes() + "/"
        // A loaded mapping's channel is checked to be 1-16; clamping keeps a hand-built one from trapping.
        channel = UInt8(clamping: mapping.midi.channel - 1)
        buttonNames = Dictionary(mapping.notes.buttons.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var ccNames: [Int: String] = [:]
        for cc in mapping.jog.ccs { ccNames[cc] = "jog" }
        ccNames[mapping.pitch.msbCC] = "pitch_msb"
        ccNames[mapping.pitch.lsbCC] = "pitch_lsb"
        ccNames[mapping.needle.cc] = "needle"
        ccNames[mapping.browse.selectTurnCC] = "select_turn"
        ccNames[mapping.browse.autoLoopSizeCC] = "auto_loop_size"
        self.ccNames = ccNames
    }

    func start() {
        send("Feedback/Resend", .int(1))
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
        let deckPrefix = (root + "Deck/\(mapping.deck.number)/").lowercased()
        guard address.hasPrefix(deckPrefix) else { return }
        let key = address.dropFirst(deckPrefix.count)
        let value = message.arguments.first?.isTrue ?? false
        switch key {
        case "playing": playing = value
        case "loaded": loaded = value
        case "sync": synced = value
        case "temposliderenabled": sliderEnabled = value
        case "loop": looping = value
        default: return
        }
        refreshLEDs()
    }

    // MARK: LEDs

    func refreshLEDs() {
        buttonLED("play", on: playing)
        refreshTransportLEDs()
        loopLEDs()
    }

    func buttonLED(_ name: String, on: Bool) {
        guard let note = mapping.notes.buttons[name] else { return }
        let idle = mapping.leds.dimUnlitButtons ? Self.dim : Self.off
        led(note, on ? Self.full : idle)
    }

    func led(_ note: Int, _ velocity: UInt8) {
        guard ledCache[note] != velocity else { return }
        ledCache[note] = velocity
        output?.send(.noteOn(channel: channel, note: UInt8(note), velocity: velocity))
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
