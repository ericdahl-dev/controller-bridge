/// Every change the app asks of the Coordinator, as one value (#386): BridgeModel sends it through the event pipe, the
/// Engine routes it by `routing` without naming it, and `apply` runs it. A new command is a case here and a call in
/// BridgeModel; nothing in the pipe or the Engine changes.
extension Coordinator {
    public enum Command: Equatable, Sendable {
        case setDeck(Int, controller: Int)
        case setDevices(input: MIDIEndpoint?, output: MIDIEndpoint?, controller: Int)
        case setLEDs(enabled: Bool)
        /// Start (a source) or end (nil) the capture window's pause of a controller (#186).
        case setCapture(source: MIDIEndpoint.ID?)
        case setDeckColors(followSyndicate: Bool, custom: DeckColors)
        case setRingColors(RingColors)
        /// Pads and ring through Denon's color message, or the 64-color table (#530).
        case setColorMessages(Bool)
        /// The OSC destination opened late (#84): ask Syndicate to resend its state, since what was sent before was dropped.
        case resync
        case setControllers([ControllerSettings])
        /// An imported mapping (#24): the controller profiles to run from now on.
        case setProfiles([ControllerProfile])
        /// Profiles chosen by hand per device name (#200).
        case setProfileChoices([String: String])
        /// Settings' jog display switch (#165).
        case setJogDisplay(enabled: Bool)
        /// Settings' display firmware (#425): Denon's or custom.
        case setDisplayFirmware(DisplayFirmware)
        /// The deck the jog display preview follows with no controller connected (#221); nil, the first loaded.
        case setJogPreviewDeck(Int?)
        /// Start the LED sweep, `delay` seconds per color; or stop it part-way (#26).
        case ledSweep(delay: Double)
        case stopLEDSweep

        /// Where a command goes while the demo (#64) has its own Coordinator.
        public enum Routing: Equatable, Sendable {
            /// A settings change: the real Coordinator gets it now, or when the demo ends, in order.
            case waitsForDemo
            /// Always the real Coordinator, demo or not.
            case real
            /// Whichever Coordinator is running: the demo's while it's on.
            case active
            /// The real Coordinator and the demo's both.
            case realAndDemo
        }

        public var routing: Routing {
            switch self {
            // A real device is captured, so the real Coordinator pauses it, demo or not.
            case .setCapture: .real
            case .ledSweep, .stopLEDSweep: .active
            // The preview's deck (#221) holds for the real controller and the demo alike.
            case .setJogPreviewDeck: .realAndDemo
            case .setDeck, .setDevices, .setLEDs, .setDeckColors, .setRingColors, .setColorMessages, .resync, .setControllers, .setProfiles,
                 .setProfileChoices, .setJogDisplay, .setDisplayFirmware:
                .waitsForDemo
            }
        }
    }

    /// Runs one command: the only place a Command becomes a call.
    public func apply(_ command: Command) {
        switch command {
        case .setDeck(let deck, let controller): setDeck(deck, controller: controller)
        case .setDevices(let input, let output, let controller): setDevices(input: input, output: output, controller: controller)
        case .setLEDs(let enabled): setLEDs(enabled: enabled)
        case .setCapture(let source): setCapture(source: source)
        case .setDeckColors(let follow, let custom): setDeckColors(followSyndicate: follow, custom: custom)
        case .setRingColors(let mode): setRingColors(mode)
        case .setColorMessages(let on): setColorMessages(on)
        case .resync: resync()
        case .setControllers(let entries): setControllers(entries)
        case .setProfiles(let profiles): setProfiles(profiles)
        case .setProfileChoices(let choices): setProfileChoices(choices)
        case .setJogDisplay(let enabled): setJogDisplay(enabled: enabled)
        case .setDisplayFirmware(let firmware): setDisplayFirmware(firmware)
        case .setJogPreviewDeck(let deck): setJogPreviewDeck(deck)
        case .ledSweep(let delay): startLEDSweep(delay: delay)
        case .stopLEDSweep: stopLEDSweep()
        }
    }
}
