/// Runs the Bridges (one per controller) against the MIDI system, the OSC sender, a clock and a log.
///
/// Not thread-safe on purpose: the app confines it to one serial consumer that feeds it MIDI, feedback and ticks in
/// order. Tests call it directly.
public final class Coordinator {
    private let midiSystem: any MIDISystem
    private let osc: any OSCSender
    private let clock: any Clock
    private let log: any LogSink
    private var controllers: [Controller]
    /// The controller profiles a device can match.
    private var profiles: [ControllerProfile]
    /// Unmatched devices already logged, so a device-list change doesn't log them again.
    private var loggedUnmatched: Set<MIDIEndpoint.ID> = []
    /// Devices matching more than one profile, already logged.
    private var loggedAmbiguous: Set<MIDIEndpoint.ID> = []
    private var bridges: [Bridge] { controllers.map(\.bridge) }
    /// Deck colors from Syndicate's palette, the defaults until one arrives (#123).
    private var syndicateDeckColors = DeckColors.defaults
    /// Settings' deck colors (#123): follow Syndicate, or the custom colors.
    private var followSyndicateDeckColors = true
    private var customDeckColors = DeckColors.defaults
    /// The deck colors in use: the ring's, and the app's badges through the status.
    var deckColors: DeckColors { followSyndicateDeckColors ? syndicateDeckColors : customDeckColors }

    /// A Bridge for a controller, with the deck colors in use.
    private func makeBridge(_ mapping: Mapping) -> Bridge {
        let bridge = Bridge(mapping: mapping, osc: osc, clock: clock)
        bridge.deckColors = deckColors
        return bridge
    }

    private var loggedBlackDecks: Set<Int> = []

    /// Logs once per deck when Syndicate's color for it is black, which DeckColors replaces with the default.
    private func noteBlackSlot(_ numbers: [Int]) -> [Int] {
        if numbers.count >= 4, numbers[0] % 2 == 1, (1...7).contains(numbers[0]), DeckColors.isBlack(numbers[1...3]) {
            let deck = (numbers[0] + 1) / 2
            if loggedBlackDecks.insert(deck).inserted {
                log.log("Syndicate's deck \(deck) color is black, which the LC6000's ring can't show; using the default")
            }
        }
        return numbers
    }

    /// Gives every Bridge the deck colors in use; each repaints its ring.
    private func applyDeckColors() {
        status.deckColors = deckColors
        for bridge in bridges { bridge.setDeckColors(deckColors) }
    }

    /// When the last feedback message arrived, if any has (#21).
    private var lastFeedbackAt: Double?
    /// When the last Resend went out, while it waits for an answer. Any feedback is the answer.
    private var resendSentAt: Double?

    /// Set while the Diagnostics window is open (#26); nil otherwise, so nothing is built for it during a set.
    /// The LED sweep in progress: when it started, its steps and the next one to send.
    private var sweep: (start: Double, steps: [LEDSweep.Step], next: Int)?

    public var diagnostics: ((DiagnosticEvent) -> Void)? {
        didSet { (osc as? OSCTap)?.onSend = diagnostics.map { sink in { sink(.oscOut($0)) } } }
    }
    /// Settings' LEDs switch, kept so a Bridge rebuilt for another profile honors it.
    private var ledsEnabled = true

    /// What the menu shows. The app copies it after each call.
    /// The profile the first controller runs: the bundled one, or an imported mapping (#24). The demo runs it (#98).
    public var runningProfile: ControllerProfile { controllers[0].profile }

    public private(set) var status: CoordinatorStatus

    /// A Bridge and the devices it is connected to.
    private struct Controller {
        var bridge: Bridge
        /// The profile the bridge runs, chosen by the connected device's name.
        var profile: ControllerProfile
        var source: MIDIEndpoint?
        /// The unique id of the last source this controller used, so a replug finds the same unit first.
        var knownSourceID: MIDIEndpoint.ID?
        /// The devices picked in Settings (#19). Nil is automatic: the first device a profile matches.
        var chosenInput: MIDIEndpoint.ID?
        var chosenOutput: MIDIEndpoint.ID?
        /// The MIDI channel picked in Settings (#25), 1-16, or nil for the profile's.
        var channel: Int?
        /// One of the deck layers of a controller that follows its own layers (#79): it shares the unit with the
        /// other layers, on its own channel.
        var followsLayers = false
        /// The entry's own setting (#133): it follows layers whenever its profile has them.
        var wantsLayers = false
        /// The destination its LEDs go to, once open.
        var destination: MIDIEndpoint?
    }

    /// One controller, whose profile is chosen by the name of the device that connects. Until one does, it runs the
    /// first profile. `profiles` must not be empty.
    public init(profiles: [ControllerProfile], midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        precondition(!profiles.isEmpty, "A Coordinator needs at least one controller profile")
        self.midiSystem = midi
        // Every Bridge sends through the tap, so the OSC log sees what goes out while Diagnostics is open.
        self.osc = OSCTap(osc)
        self.clock = clock
        self.log = log
        self.profiles = profiles
        let first = profiles[0]
        controllers = [Controller(bridge: Bridge(mapping: first.mapping, osc: self.osc, clock: clock), profile: first)]
        status = CoordinatorStatus(controllers: [ControllerStatus(deck: first.mapping.deck.number, connected: false)])
    }

    /// One controller running `mapping`, matched to a device whose name contains `mapping.midi.input`.
    public convenience init(mapping: Mapping, midi: any MIDISystem, osc: any OSCSender, clock: any Clock, log: any LogSink) {
        let profile = ControllerProfile(id: "custom", name: "Custom mapping", deviceHints: [mapping.midi.input], mapping: mapping)
        self.init(profiles: [profile], midi: midi, osc: osc, clock: clock, log: log)
    }

    /// Opens each controller's ports, asks Syndicate for its state and paints the LEDs. Starting with no controller
    /// connected is not an error: it connects when it appears.
    ///
    /// With the saved `controllers` and LEDs switch (#105), every controller is set up first and only then connected,
    /// so it never touches a device, deck or LED the user didn't choose. Nil keeps what's set: the automatic start at
    /// launch, and the current controllers and LEDs switch on a restart (after the demo).
    public func start(controllers entries: [ControllerSettings]? = nil, ledsEnabled: Bool? = nil) {
        if let ledsEnabled { self.ledsEnabled = ledsEnabled }
        if let entries, !entries.isEmpty {
            for (index, entry) in entries.enumerated() { configure(index, as: entry) }
        }
        for bridge in bridges { bridge.setLEDsEnabled(self.ledsEnabled) }
        refreshDevices()
        for index in controllers.indices {
            if !connect(index) {
                log.log("No controller matching \"\(controllers[index].bridge.mapping.midi.input)\" yet")
            }
            controllers[index].bridge.start()
        }
        requestResend()
    }

    /// The MIDI devices changed. Re-reads them, connecting controllers that appeared.
    public func devicesChanged() {
        refreshDevices()
        for index in controllers.indices {
            if let source = controllers[index].source {
                if !midiSystem.sources.contains(where: { $0.id == source.id }) {
                    disconnect(index, reason: .unplugged)
                } else if controllers[index].bridge.output == nil {
                    // Its input connected before its output port appeared (#148): open the port now and paint into it.
                    openOutput(index, for: source, profile: controllers[index].profile)
                    if controllers[index].bridge.output != nil { controllers[index].bridge.repaintLEDs() }
                }
            } else if connect(index) {
                controllers[index].bridge.start()
                requestResend()
            }
        }
        disconnectFailedOutputs()
    }

    /// Reading from a source failed, such as a reconnect that couldn't attach. Counts as that controller's unplug.
    public func inputFailed(source: MIDIEndpoint.ID) {
        for index in controllers.indices where controllers[index].source?.id == source {
            disconnect(index, reason: .inputFailed)
        }
    }

    /// Releases everything the controller held, exactly once, and closes its ports.
    private func disconnect(_ index: Int, reason: DisconnectReason) {
        guard let source = controllers[index].source else { return }
        let bridge = controllers[index].bridge
        bridge.releaseAll()
        controllers[index].source = nil
        let destination = controllers[index].destination
        controllers[index].destination = nil
        // Another controller on the same device, on another channel (#25), keeps it open.
        if !controllers.contains(where: { $0.source?.id == source.id }) { midiSystem.disconnect(source: source) }
        if destination == nil || !controllers.contains(where: { $0.destination?.id == destination?.id }) { bridge.output?.close() }
        bridge.output = nil
        status.controllers[index].profile = nil
        status.controllers[index].lastDisconnect = reason
        let detail: String? = switch reason {
        case .sendFailed: "MIDI send failed"
        case .inputFailed: "MIDI input failed"
        case .unplugged, .deviceChanged, .removed, .stopped: nil
        }
        report(index, "Disconnected \(source.name)" + (detail.map { " (\($0))" } ?? ""))
    }

    /// Whether two controllers are layers of one unit: both follow layers, on different channels. Two following
    /// entries on one channel would put two decks on one layer, so they don't share.
    private func sharesLayers(_ a: Int, with b: Int) -> Bool {
        guard controllers[a].followsLayers, controllers[b].followsLayers else { return false }
        let channelA = controllers[a].bridge.mapping.midi.channel, channelB = controllers[b].bridge.mapping.midi.channel
        guard channelA != channelB, let source = controllers[b].source else { return channelA != channelB }
        // Another layer already on this unit with my channel means this unit's layer is taken.
        return !controllers.indices.contains { $0 != a && controllers[$0].source?.id == source.id
            && controllers[$0].followsLayers && controllers[$0].bridge.mapping.midi.channel == channelA }
    }

    /// Opens the controller's ports if a matching device is present. Returns whether its input is connected.
    private func connect(_ index: Int) -> Bool {
        let sources = midiSystem.sources
        let source: MIDIEndpoint?
        if let chosen = controllers[index].chosenInput {
            source = sources.first { $0.id == chosen }
        } else {
            // Automatic: a unit another controller already has stays with it, except that a controller following its
            // own layers shares its unit with its other layers, each on its own channel (#79).
            let claimed = Set(controllers.indices.filter { $0 != index && !sharesLayers(index, with: $0) }
                .compactMap { controllers[$0].source?.id })
            let free = sources.filter { !claimed.contains($0.id) }
            let known = controllers[index].knownSourceID.flatMap { id in free.first { $0.id == id } }
            source = known ?? free.first { ControllerProfile.matching($0.name, in: profiles) != nil }
        }
        guard let source else { return false }
        // A device picked in Settings runs even if no profile names it: then it keeps the current profile.
        let matchedProfile = ControllerProfile.matching(source.name, in: profiles)
        guard let profile = matchedProfile ?? (controllers[index].chosenInput != nil ? controllers[index].profile : nil) else {
            return false
        }
        if profile != controllers[index].profile {
            controllers[index].profile = profile
            controllers[index].bridge = makeBridge(profile, for: index)
        }
        let bridge = controllers[index].bridge
        do {
            if !controllers.contains(where: { $0.source?.id == source.id }) { try midiSystem.connect(source: source) }
        } catch {
            log.log("Couldn't open MIDI input \(source.name): \(error)")
            return false
        }
        controllers[index].source = source
        controllers[index].knownSourceID = source.id
        status.controllers[index].profile = profile.name
        status.controllers[index].lastProfile = profile.name
        openOutput(index, for: source, profile: profile)
        report(index, "Connected \(source.name)")
        return true
    }

    /// Opens the LED output for a connected controller: the chosen one, else the port named like its input, else
    /// the mapping's hint, never a port the profile excludes. Logs where the LEDs go, or that they have nowhere to go.
    private func openOutput(_ index: Int, for source: MIDIEndpoint, profile: ControllerProfile) {
        let bridge = controllers[index].bridge
        let destinations = midiSystem.destinations
        let chosenOutput = controllers[index].chosenOutput.flatMap { id in destinations.first { $0.id == id } }
        // Layers of one unit share its port both ways (#79): a destination another layer has isn't taken from this one.
        let taken = Set(controllers.indices.filter { $0 != index && !sharesLayers(index, with: $0) }
            .compactMap { controllers[$0].destination?.id })
        let freeDestinations = controllers[index].chosenInput == nil ? destinations.filter { !taken.contains($0.id) } : destinations
        // The LEDs go back to the port the controls came from: same name first, then the name hint (#99).
        let sameName = freeDestinations.first { $0.name == source.name }
        // Never a port the profile excludes, such as the LC6000's jog display (WD): its "LC6000" matches the hint too.
        let allowed = freeDestinations.filter { destination in
            !profile.excludeHints.contains { destination.name.lowercased().contains($0.lowercased()) }
        }
        if let destination = chosenOutput ?? sameName ?? Self.match(allowed, bridge.mapping.midi.output) {
            do {
                bridge.output = try midiSystem.openOutput(destination: destination)
                controllers[index].destination = destination
            } catch {
                log.log("Couldn't open MIDI output \(destination.name): \(error)")
            }
        }
    }

    /// Lists every MIDI source with the profile it matches. A source that matches none is listed, not bridged.
    private func refreshDevices() {
        status.devices = midiSystem.sources.map { source in
            if let profile = ControllerProfile.matching(source.name, in: profiles) {
                let names = ControllerProfile.candidates(source.name, in: profiles).map(\.profile.name)
                if names.count > 1, loggedAmbiguous.insert(source.id).inserted {
                    log.log("\(source.name) matches \(names.joined(separator: " and ")); using \(profile.name), whose hint is longest.")
                }
                return DeviceStatus(name: source.name, profile: profile.name, note: nil)
            }
            let note = "No controller profile matches \(source.name), so it isn't bridged."
            if loggedUnmatched.insert(source.id).inserted { log.log(note) }
            return DeviceStatus(name: source.name, profile: nil, note: note)
        }
    }

    private func report(_ index: Int, _ event: String) {
        log.log(event)
        status.controllers[index].connected = controllers[index].source != nil
        status.controllers[index].outputOpen = controllers[index].bridge.output != nil
        status.controllers[index].lastEvent = event
    }

    /// Releases everything held in Syndicate. Safe to call again: a second call sends nothing.
    public func stop() {
        for index in controllers.indices {
            controllers[index].bridge.releaseAll()
            disconnect(index, reason: .stopped)
        }
    }

    /// The Mac is about to sleep: release everything held, since the controller may be gone on wake.
    public func willSleep() {
        for bridge in bridges { bridge.releaseAll() }
    }

    /// The Mac woke: the devices may have changed while it slept.
    public func didWake() {
        devicesChanged()
    }

    /// Runs timers, such as releasing a jog nudge after the wheel stops. The app calls it about every 10 ms.
    public func tick() {
        runSweep()
        for bridge in bridges { bridge.tick() }
        checkLiveness()
        disconnectFailedOutputs()
    }

    /// The first endpoint whose name contains `wanted`, ignoring case.
    private static func match(_ endpoints: [MIDIEndpoint], _ wanted: String) -> MIDIEndpoint? {
        endpoints.first { $0.name.lowercased().contains(wanted.lowercased()) }
    }

    /// A MIDI message from a source. Only the controller connected to that source handles it.
    public func midi(_ event: MIDIEvent, source: MIDIEndpoint.ID) {
        let mapping = (controllers.first { $0.source?.id == source } ?? controllers[0]).bridge.mapping
        // Notes the controller sends on its own, such as the LC6000's idle heartbeat (#103), reach nothing.
        if case .noteOn(_, let note, _) = event, mapping.midi.ignoreNotes.contains(Int(note)) { return }
        if case .noteOff(_, let note, _) = event, mapping.midi.ignoreNotes.contains(Int(note)) { return }
        if let diagnostics {
            diagnostics(.midiIn(event, label: mapping.monitorName(for: event), at: clock.now))
        }
        let routed = layerHandover(event, source: source)
        for index in controllers.indices where controllers[index].source?.id == source {
            controllers[index].bridge.handle(routed)
            for notice in controllers[index].bridge.notices { log.log(notice) }
            controllers[index].bridge.notices.removeAll()
        }
        disconnectFailedOutputs()
    }

    /// Units seen sending controls on a layer's own channel (#79): the LC6000's multi-channel state. Others are in
    /// the normal state, every control on ch1.
    private var multiChannelUnits: Set<MIDIEndpoint.ID> = []

    /// The controller's own deck layers (#79), as the LC6000 really behaves (the CoS's captures):
    /// - note 51 at 127 on channel N makes layer N active; its note 51 at 0 always comes on ch1 and means nothing;
    /// - in its normal state every control stays on ch1, so ch1 controls go to the active layer's deck;
    /// - in the other state seen (controls on the layer's own channel), a control on channel N goes to deck N and
    ///   makes layer N active.
    /// Returns the event as the layers should see it: a ch1 control re-addressed to the active layer's channel.
    private func layerHandover(_ event: MIDIEvent, source: MIDIEndpoint.ID) -> MIDIEvent {
        let layers = controllers.indices.filter { controllers[$0].source?.id == source && controllers[$0].followsLayers }
        guard let first = layers.first else { return event }
        let (channel, note, velocity): (UInt8, UInt8?, UInt8) = switch event {
        case .noteOn(let c, let n, let v): (c, n, v)
        case .noteOff(let c, let n, _): (c, n, 0)
        case .controlChange(let c, _, let v): (c, nil, v)
        }
        let layerChannel = { (index: Int) in self.controllers[index].bridge.mapping.midi.channel }
        let current = layers.first { status.controllers[$0].activeLayer } ?? first
        if let note, Int(note) == controllers[first].bridge.mapping.midi.layerNote {
            if velocity > 0, let target = layers.first(where: { layerChannel($0) == Int(channel) + 1 }), target != current {
                activateLayer(target, leaving: current, among: layers, multiChannel: multiChannelUnits.contains(source))
            }
            return event
        }
        if channel == 0 {
            // The normal state: controls on ch1. The active layer's LEDs go out where its controls are.
            if layerChannel(current) != 1 { multiChannelUnits.remove(source) }
            setLEDChannel(0, for: current)
            return layerChannel(current) == 1 ? event : event.onChannel(UInt8(layerChannel(current) - 1))
        }
        // Controls on a layer's own channel: that layer is the one in use, and the unit is in its multi-channel state.
        multiChannelUnits.insert(source)
        guard let target = layers.first(where: { layerChannel($0) == Int(channel) + 1 }) else { return event }
        if target != current { activateLayer(target, leaving: current, among: layers, multiChannel: true) }
        status.controllers[target].activeLayer = true
        setLEDChannel(nil, for: target)
        return event
    }

    /// One handover: the layer left releases what it held and stops writing LEDs; the new one becomes the only active
    /// layer and waits for the shared fader's pickup. Its LEDs go out where the unit's controls come: ch1 in the
    /// normal state, the layer's own channel in the multi-channel state.
    private func activateLayer(_ target: Int, leaving current: Int, among layers: [Int], multiChannel: Bool) {
        if current != target { controllers[current].bridge.releaseAll() }
        for index in layers where index != target {
            status.controllers[index].activeLayer = false
            controllers[index].bridge.layerShown = false
        }
        status.controllers[target].activeLayer = true
        controllers[target].bridge.ledChannel = multiChannel || controllers[target].bridge.mapping.midi.channel == 1 ? nil : 0
        controllers[target].bridge.becameActiveLayer()
    }

    /// Where a layer's LEDs go; repaints there if it moved.
    private func setLEDChannel(_ channel: UInt8?, for index: Int) {
        let bridge = controllers[index].bridge
        let effective = channel == 0 && bridge.mapping.midi.channel == 1 ? nil : channel
        guard bridge.ledChannel != effective else { return }
        bridge.ledChannel = effective
        if bridge.layerShown { bridge.becameActiveLayer() }
    }

    /// An OSC feedback message from Syndicate. One listener fans out to every Bridge.
    public func feedback(_ message: OSCMessage) {
        // Syndicate's deck colors are cue palette slots 1, 3, 5 and 7 (#123).
        // Several slots may come in one message (OSC arrays, flattened): one group of four per slot.
        if message.address.lowercased().hasSuffix("/colorpalette") {
            let numbers = message.arguments.compactMap(\.wholeNumber)
            var colors = syndicateDeckColors
            for start in stride(from: 0, to: numbers.count - 3, by: 4) {
                if let updated = colors.updated(byPalette: noteBlackSlot(Array(numbers[start..<(start + 4)]))) { colors = updated }
            }
            if colors != syndicateDeckColors {
                syndicateDeckColors = colors
                applyDeckColors()
            }
        }
        diagnostics?(.oscIn(message))
        feedbackArrived()
        for bridge in bridges { bridge.handle(message) }
        for index in controllers.indices { status.controllers[index].master = controllers[index].bridge.isMaster }
        disconnectFailedOutputs()
    }

    /// A failed MIDI send means the controller is gone, even before CoreMIDI says so.
    private func disconnectFailedOutputs() {
        for index in controllers.indices where controllers[index].bridge.outputFailed {
            disconnect(index, reason: .sendFailed)
        }
    }

    // MARK: Feedback liveness (#21)

    // Syndicate sends feedback only when a value changes, so after a quiet spell the bridge asks for a resend: a live
    // Syndicate answers with every subscribed value, and always ColorPalette (user guide §14.10).

    /// The OSC settings are shared by every controller; the first one's mapping holds them until Settings (#19).
    private var oscSettings: Mapping.OSC { controllers[0].bridge.mapping.osc }

    private func feedbackArrived() {
        let now = clock.now
        let wasStale = status.feedback == .stale
        // An answer to a Resend still in its answer window is the full state already.
        let answering = resendSentAt.map { now - $0 < Double(oscSettings.feedbackAnswerMs) / 1000 } ?? false
        lastFeedbackAt = now
        resendSentAt = nil
        status.feedback = .live
        guard wasStale else { return }
        log.log("Syndicate feedback is back")
        for bridge in bridges { bridge.start() }
        if !answering { requestResend() }
    }

    private func checkLiveness() {
        let now = clock.now
        if let last = lastFeedbackAt, resendSentAt == nil, now - last >= Double(oscSettings.feedbackQuietMs) / 1000 {
            requestResend()
        }
        if status.feedback == .live, let sent = resendSentAt, now - sent >= Double(oscSettings.feedbackAnswerMs) / 1000 {
            feedbackStopped()
        }
        // Not live: ask again every quiet period, so a Syndicate that comes back quietly is found.
        if status.feedback != .live, let sent = resendSentAt, now - sent >= Double(oscSettings.feedbackQuietMs) / 1000 {
            resendSentAt = nil
            requestResend()
        }
    }

    /// Syndicate didn't answer: show idle for its state until it's back.
    private func feedbackStopped() {
        let event = "Syndicate feedback stopped"
        status.feedback = .stale
        status.lastDropout = event
        log.log(event)
        for bridge in bridges { bridge.clearSyndicateState() }
    }

    /// Settings (#19): the controller drives another deck from now on. Held controls are released on the old one,
    /// then the controller resyncs.
    public func setDeck(_ deck: Int, controller index: Int) {
        guard controllers.indices.contains(index), controllers[index].bridge.mapping.deck.number != deck else { return }
        controllers[index].bridge.switchDeck(to: deck)
        status.controllers[index].deck = deck
        requestResend()
        disconnectFailedOutputs()
    }

    /// Settings (#19): the controller uses these devices from now on, or nil for automatic. Held controls are
    /// released and the old ports closed first, then the controller connects and resyncs.
    public func setDevices(input: MIDIEndpoint?, output: MIDIEndpoint?, controller index: Int) {
        guard controllers.indices.contains(index) else { return }
        controllers[index].chosenInput = input?.id
        controllers[index].chosenOutput = output?.id
        controllers[index].knownSourceID = input?.id
        disconnect(index, reason: .deviceChanged)
        if connect(index) {
            controllers[index].bridge.start()
            requestResend()
        }
        disconnectFailedOutputs()
    }

    /// Settings (#25): the controller entries, one per controller. Existing controllers take their entry's changes;
    /// new entries connect and resync.
    public func setControllers(_ entries: [ControllerSettings]) {
        // At least one controller always runs, so start() and the status have someone to show.
        guard !entries.isEmpty else { return }
        while controllers.count > entries.count { removeLastController() }
        for index in entries.indices {
            if index < controllers.count {
                update(index, to: entries[index])
            } else {
                addController(entries[index])
            }
        }
    }

    // Kept as separate small functions: Xcode 26.6's optimizer crashed (CopyPropagation) on one loop doing all three.

    private func removeLastController() {
        let last = controllers.count - 1
        controllers[last].bridge.releaseAll()
        disconnect(last, reason: .removed)
        controllers.removeLast()
        status.controllers.removeLast()
    }

    /// Sets controller `index` up as `entry` says, adding it if it's new, without connecting anything: start (#105)
    /// connects them all afterwards.
    private func configure(_ index: Int, as entry: ControllerSettings) {
        let profile = profiles[0]
        if index == controllers.count {
            controllers.append(Controller(bridge: makeBridge( profile.mapping), profile: profile))
            status.controllers.append(ControllerStatus(deck: entry.deck, connected: false))
        }
        status.controllers[index].deck = entry.deck
        controllers[index].channel = entry.channel
        controllers[index].wantsLayers = entry.followLayers == true
        deriveFollowing(index)
        controllers[index].chosenInput = entry.input?.id
        controllers[index].chosenOutput = entry.output?.id
        controllers[index].knownSourceID = entry.input?.id
        controllers[index].bridge = makeBridge(controllers[index].profile, for: index)
        // A device chosen in Settings: until it connects, the panel says WAITING for it (#91), as after a change.
        if entry.input != nil { status.controllers[index].lastDisconnect = .deviceChanged }
    }

    private func addController(_ entry: ControllerSettings) {
        let first = profiles[0]
        let index = controllers.count
        status.controllers.append(ControllerStatus(deck: entry.deck, connected: false))
        var controller = Controller(bridge: makeBridge( first.mapping), profile: first)
        controller.channel = entry.channel
        controller.wantsLayers = entry.followLayers == true
        controllers.append(controller)
        deriveFollowing(index)
        controllers[index].bridge = makeBridge(first, for: index)
        setDevices(input: entry.input, output: entry.output, controller: index)
    }

    private func update(_ index: Int, to entry: ControllerSettings) {
        controllers[index].wantsLayers = entry.followLayers == true
        deriveFollowing(index)
        setDeck(entry.deck, controller: index)
        if entry.channel != controllers[index].channel {
            controllers[index].channel = entry.channel
            setChannel(index)
        }
        let devicesChanged = entry.input?.id != controllers[index].chosenInput || entry.output?.id != controllers[index].chosenOutput
        if devicesChanged { setDevices(input: entry.input, output: entry.output, controller: index) }
    }

    /// Rebuilds the controller's Bridge on its new channel: held controls are released first, the ports stay open.
    private func setChannel(_ index: Int) {
        let old = controllers[index].bridge
        old.releaseAll()
        let bridge = makeBridge(controllers[index].profile, for: index)
        bridge.output = old.output
        controllers[index].bridge = bridge
        guard controllers[index].source != nil else { return }
        bridge.start()
        requestResend()
    }

    /// A Bridge running `profile` with this controller's settings: its deck, channel and the LEDs switch.
    private func makeBridge(_ profile: ControllerProfile, for index: Int) -> Bridge {
        var mapping = profile.mapping
        // The deck and channel are settings, not part of the profile.
        mapping.deck.number = status.controllers[index].deck
        if let channel = controllers[index].channel { mapping.midi.channel = channel }
        let bridge = makeBridge( mapping)
        bridge.setLEDsEnabled(ledsEnabled)
        bridge.layerShown = layerInFront(index, channel: mapping.midi.channel, layers: profile.mapping.midi.layers)
        return bridge
    }

    /// Whether this controller's LEDs are the ones the unit shows (#79): any controller that doesn't follow layers;
    /// the active layer; or, before any handover, the profile's first layer.
    private func layerInFront(_ index: Int, channel: Int, layers: [Mapping.Layer]) -> Bool {
        guard controllers[index].followsLayers else { return true }
        if status.controllers[index].activeLayer { return true }
        let anyActive = controllers.indices.contains { $0 != index && controllers[$0].followsLayers && status.controllers[$0].activeLayer }
        return !anyActive && channel == layers.first?.channel
    }

    /// An imported mapping (#24): these profiles replace the current ones. A controller whose profile changed releases
    /// its held controls first, then runs the new one on the same ports with its settings (deck, channel, LEDs) kept,
    /// and the bridge resyncs once.
    public func setProfiles(_ newProfiles: [ControllerProfile]) {
        guard !newProfiles.isEmpty else { return }
        profiles = newProfiles
        var resync = false
        for index in controllers.indices where swapProfile(index, from: newProfiles) { resync = true }
        if resync { requestResend() }
        disconnectFailedOutputs()
    }

    /// Follows layers when the entry asks to and its profile has them (#133). A profile without layers can't be
    /// followed: the entry falls back to its own deck, with no layer active (#115).
    private func deriveFollowing(_ index: Int) {
        let follows = controllers[index].wantsLayers && !controllers[index].profile.mapping.midi.layers.isEmpty
        controllers[index].followsLayers = follows
        status.controllers[index].followsLayers = follows
        if !follows { status.controllers[index].activeLayer = false }
    }

    /// One controller's part of `setProfiles`: returns whether it is connected and now runs a changed profile.
    /// Its own function, as Xcode 26.6's optimizer crashed on loops that mutate `controllers` inline (#65).
    private func swapProfile(_ index: Int, from newProfiles: [ControllerProfile]) -> Bool {
        guard let updated = newProfiles.first(where: { $0.id == controllers[index].profile.id }),
              updated != controllers[index].profile else { return false }
        let old = controllers[index].bridge
        old.releaseAll()
        let wasFollowing = controllers[index].followsLayers
        controllers[index].profile = updated
        deriveFollowing(index)
        let bridge = makeBridge(updated, for: index)
        bridge.output = old.output
        bridge.carrySyndicateState(from: old)
        bridge.carryOwnState(from: old)
        // The active layer's LEDs keep going where the unit's controls come from (#79).
        if wasFollowing, controllers[index].followsLayers { bridge.ledChannel = old.ledChannel }
        controllers[index].bridge = bridge
        guard controllers[index].source != nil else { return false }
        status.controllers[index].profile = updated.name
        bridge.start(stale: old.feedbackStale)
        return true
    }

    /// Asks Syndicate to resend its state (#84): the OSC destination opened late, so what was sent before was dropped.
    public func resync() {
        // A Resend still "waiting" went out before there was anywhere to send it.
        resendSentAt = nil
        requestResend()
    }

    /// Settings' deck colors (#123): the ring repaints, and the status carries them to the badges.
    public func setDeckColors(followSyndicate: Bool, custom: DeckColors) {
        followSyndicateDeckColors = followSyndicate
        customDeckColors = custom
        applyDeckColors()
        disconnectFailedOutputs()
    }

    /// Settings (#19): the LEDs switch, for every controller.
    public func setLEDs(enabled: Bool) {
        ledsEnabled = enabled
        for bridge in bridges { bridge.setLEDsEnabled(enabled) }
        disconnectFailedOutputs()
    }

    /// The one place a Resend is sent. One already waiting for its answer isn't sent again.
    private func requestResend() {
        guard resendSentAt == nil else { return }
        resendSentAt = clock.now
        controllers[0].bridge.send("Feedback/Resend", .int(1))
    }

    // MARK: LED sweep (#26)

    /// Starts the LED sweep on the first controller, `delay` seconds per color (0.6, as the Python led-sweep).
    public func startLEDSweep(delay: Double = 0.6) {
        let bridge = controllers[0].bridge
        guard bridge.output != nil else {
            diagnostics?(.sweep("No controller output is open, so there is nothing to sweep."))
            return
        }
        bridge.ledsHeld = true
        sweep = (clock.now, LEDSweep.steps(for: bridge.mapping, delay: delay), 0)
        status.sweeping = true
        runSweep()
    }

    /// Whether an LED sweep is running.
    public var isSweeping: Bool { sweep != nil }

    /// Stops the sweep part-way. Its remaining steps are dropped, and the LEDs repaint.
    public func stopLEDSweep() {
        guard sweep != nil else { return }
        sweep = nil
        diagnostics?(.sweep("LED sweep stopped."))
        endSweep()
    }

    /// Gives the LEDs back to the bridge, painted from its current state.
    private func endSweep() {
        status.sweeping = false
        let bridge = controllers[0].bridge
        bridge.ledsHeld = false
        bridge.repaintLEDs()
    }

    /// Sends every sweep step that is due.
    private func runSweep() {
        guard var current = sweep else { return }
        let bridge = controllers[0].bridge
        while current.next < current.steps.count, clock.now - current.start >= current.steps[current.next].at {
            let step = current.steps[current.next]
            for send in step.sends { bridge.sweepLED(send.note, send.velocity) }
            for caption in step.captions { diagnostics?(.sweep(caption)) }
            current.next += 1
        }
        if current.next < current.steps.count {
            sweep = current
        } else {
            sweep = nil
            endSweep()
        }
    }
}
