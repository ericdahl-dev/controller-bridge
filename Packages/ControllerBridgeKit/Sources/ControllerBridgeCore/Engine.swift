/// The one consumer of an EventPipe: it feeds each event to the Coordinator, in order, on one task.
///
/// No Task per message. The app runs `run(_:)` once, on whatever single executor owns the Coordinator.
public struct Engine {
    private let coordinator: Coordinator
    private let log: any LogSink
    private let onDiagnostic: (@Sendable (DiagnosticEvent) -> Void)?
    /// Makes the demo (#64) when it's turned on; nil, and the demo event does nothing.
    private let makeDemo: (@Sendable (ControllerProfile) -> DemoSession)?
    private let onStatus: (@Sendable (CoordinatorStatus) -> Void)?

    /// `onStatus` gets the Coordinator's status when the loop starts and again each time it changes, on the loop's
    /// task. The app hops it to the main actor once per change.
    public init(
        coordinator: Coordinator, log: any LogSink, onStatus: (@Sendable (CoordinatorStatus) -> Void)? = nil,
        onDiagnostic: (@Sendable (DiagnosticEvent) -> Void)? = nil,
        makeDemo: (@Sendable (ControllerProfile) -> DemoSession)? = nil
    ) {
        self.makeDemo = makeDemo
        self.coordinator = coordinator
        self.log = log
        self.onStatus = onStatus
        self.onDiagnostic = onDiagnostic
    }

    /// Returns when the pipe finishes, or right after a stop.
    public func run(_ events: AsyncStream<PipeEvent>) async {
        // The demo (#64) swaps in its own Coordinator; the real one is stopped meanwhile.
        var demo: DemoSession?
        var diagnosticsOpen = false
        // Settings changes made during the demo wait for the real controller.
        var waiting: [PipeEvent] = []
        var active: Coordinator { demo?.coordinator ?? coordinator }
        var status: CoordinatorStatus { demo?.status ?? coordinator.status }

        func setDiagnostics(_ target: Coordinator, open: Bool) {
            if open, let sink = onDiagnostic { target.diagnostics = { sink($0) } } else { target.diagnostics = nil }
        }

        func apply(_ event: PipeEvent) {
            switch event {
            case .setDeck(let deck, let controller): coordinator.setDeck(deck, controller: controller)
            case .setDevices(let input, let output, let controller):
                coordinator.setDevices(input: input, output: output, controller: controller)
            case .setLEDs(let enabled): coordinator.setLEDs(enabled: enabled)
            case .setDeckColors(let follow, let custom): coordinator.setDeckColors(followSyndicate: follow, custom: custom)
            case .setRingColors(let mode): coordinator.setRingColors(mode)
            case .resync: coordinator.resync()
            case .setControllers(let entries): coordinator.setControllers(entries)
            case .setProfiles(let profiles): coordinator.setProfiles(profiles)
            case .setProfileChoices(let choices): coordinator.setProfileChoices(choices)
            case .setJogDisplay(let enabled): coordinator.setJogDisplay(enabled: enabled)
            default: break
            }
        }

        var reported = status
        onStatus?(reported)
        for await event in events {
            defer {
                if status != reported {
                    reported = status
                    onStatus?(reported)
                }
            }
            switch event {
            case .midi(let midi, let source):
                // The real controller is stopped during the demo.
                if demo == nil { coordinator.midi(midi, source: source) }
            case .udp(let datagram):
                guard demo == nil else { continue }
                do {
                    for message in try OSCPacket(decoding: datagram).messages { coordinator.feedback(message) }
                } catch {
                    log.log("Dropped a feedback datagram (\(datagram.count) bytes): \(error)")
                }
            case .tick:
                if let demo { demo.tick() } else { coordinator.tick() }
            case .devicesChanged:
                // The real controller re-reads the devices when the demo ends.
                if demo == nil { coordinator.devicesChanged() }
            case .sleep: active.willSleep()
            case .wake: if demo == nil { coordinator.didWake() }
            // Only while the window is open does the Coordinator build anything for it.
            case .diagnostics(let open):
                diagnosticsOpen = open
                setDiagnostics(active, open: open)
            // A real device is captured, so the real Coordinator pauses it, demo or not.
            case .setCapture(let source): coordinator.setCapture(source: source)
            case .ledSweep(let delay): active.startLEDSweep(delay: delay)
            case .stopLEDSweep: active.stopLEDSweep()
            // The real unit's display answers the real Coordinator, demo or not.
            case .jogDisplayReply(let bytes): coordinator.jogDisplayReply(bytes)
            case .setDeck, .setDevices, .setLEDs, .setDeckColors, .setRingColors, .setControllers, .setProfiles, .resync,
                 .setJogDisplay, .setProfileChoices:
                if demo == nil { apply(event) } else { waiting.append(event) }
            case .demo(let on):
                if on, demo == nil, let makeDemo {
                    coordinator.stop()
                    setDiagnostics(coordinator, open: false)
                    // The profile running now, so an imported mapping shows in the demo too (#98).
                    let session = makeDemo(coordinator.runningProfile)
                    setDiagnostics(session.coordinator, open: diagnosticsOpen)
                    session.start()
                    demo = session
                } else if !on, let session = demo {
                    session.stop()
                    demo = nil
                    for change in waiting { apply(change) }
                    waiting.removeAll()
                    setDiagnostics(coordinator, open: diagnosticsOpen)
                    coordinator.start()
                }
            case .stop:
                // Releases are sent synchronously, so they have all gone out once run() returns.
                demo?.stop()
                coordinator.stop()
                return
            }
        }
    }
}
