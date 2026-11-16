import Foundation

/// The capture window's model (#186): choose the ports, walk the prompts, done. The view shows it and forwards the
/// owner's buttons and the MIDI; every rule about what's allowed when lives here, on an injected clock.
public struct CaptureFlow: Sendable {
    public enum Phase: Equatable, Sendable { case ports, steps, done }

    /// How long the idle step listens before Next, in seconds.
    public static let idleSeconds = 5.0

    public let prompts: [CapturePrompt]
    public let appVersion: String
    public private(set) var phase: Phase = .ports
    private var session: CaptureSession?
    private var stepStart = 0.0
    /// What VoiceOver last heard about: the step, and the detection on it.
    private var announcedStep: Int?
    private var announcedDetection: [String] = []
    private var announcedDone = false
    /// The idle step whose Next became available, to be announced once.
    private var idleReadyStep: Int?
    private var announcedIdleReady: Int?

    public init(prompts: [CapturePrompt] = CapturePrompts.djController, appVersion: String) {
        self.prompts = prompts
        self.appVersion = appVersion
    }

    /// Starts the steps on the chosen device and ports, at host time `time` in seconds.
    public mutating func start(device: String, ports: CapturePorts, at time: Double) {
        session = CaptureSession(appVersion: appVersion, device: device, ports: ports, prompts: prompts)
        stepStart = time
        phase = prompts.isEmpty ? .done : .steps
    }

    public var prompt: CapturePrompt? { phase == .steps ? session?.current : nil }

    /// The current step, from 1.
    public var stepNumber: Int { (session?.finishedCount ?? 0) + 1 }
    public var stepCount: Int { prompts.count }

    /// What the current step has detected so far. A busy control (a jog spin is hundreds of messages) would make
    /// working it out on every message too slow, so it's worked out at once for the first detection, then at most
    /// every `refreshInterval`, and on `tick` for whatever came since.
    public private(set) var detected: [ControlFacts] = []
    public static let refreshInterval = 0.1
    private var lastRefresh = -Double.infinity
    private var stale = false

    /// The owner's optional note, as typed. The file holds it trimmed, or no note when it's blank.
    public var note = "" {
        didSet {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            session?.note = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// The capture file, once the steps start.
    public var file: CaptureFile? { session?.file }

    public mutating func receive(_ bytes: [UInt8], at time: Double, port: Int = 0) {
        guard phase == .steps else { return }
        session?.receive(bytes, at: time, port: port)
        if detected.isEmpty || time - lastRefresh >= Self.refreshInterval { refresh(at: time) } else { stale = true }
    }

    /// The app's clock, a few times a second: shows what arrived since the last refresh.
    public mutating func tick(at time: Double) {
        if stale { refresh(at: time) }
        if prompt?.gesture == .idle, canNext(at: time) { idleReadyStep = stepNumber }
    }

    private mutating func refresh(at time: Double? = nil) {
        detected = phase == .steps ? session?.currentControls ?? [] : []
        stale = false
        if let time { lastRefresh = time }
    }

    /// Whole seconds left before the idle step's Next, or nil on any other step.
    public func idleSecondsLeft(at now: Double) -> Int? {
        guard prompt?.gesture == .idle else { return nil }
        return max(0, Int((Self.idleSeconds - (now - stepStart)).rounded(.up)))
    }

    public func canNext(at now: Double) -> Bool {
        guard let prompt else { return false }
        return prompt.gesture == .idle ? now - stepStart >= Self.idleSeconds : !detected.isEmpty
    }

    public var canRedo: Bool { prompt.map { $0.gesture != .idle } == true && session?.hasTake == true }
    public var canSkip: Bool { prompt.map { $0.gesture != .idle } == true }

    public mutating func next(at time: Double) {
        guard canNext(at: time) else { return }
        session?.confirm(at: time)
        moved(at: time)
    }

    public mutating func redo(at time: Double) {
        guard prompt != nil else { return }
        session?.redo(at: time)
        stepStart = time
        refresh()
    }

    public mutating func skip(at time: Double) {
        guard canSkip else { return }
        session?.skip(at: time)
        moved(at: time)
    }

    private mutating func moved(at time: Double) {
        stepStart = time
        if session?.current == nil { phase = .done }
        refresh()
    }

    /// What VoiceOver should announce now, if anything: a new prompt, a change in what's detected, or the end. Each
    /// is said once; the app calls this after every update.
    public mutating func takeAnnouncement() -> String? {
        switch phase {
        case .ports: return nil
        case .done:
            guard !announcedDone else { return nil }
            announcedDone = true
            let steps = file?.steps ?? []
            let skipped = steps.filter { $0.status == .skipped }.count
            return "Capture finished: \(steps.count) steps, \(skipped) skipped."
        case .steps:
            let detection = detected.map(\.spoken)
            if announcedStep != stepNumber, let prompt {
                announcedStep = stepNumber
                announcedDetection = detection
                return "Step \(stepNumber) of \(stepCount). \(prompt.text)"
            }
            if let ready = idleReadyStep, ready == stepNumber, announcedIdleReady != ready {
                announcedIdleReady = ready
                return "Done listening. Next is available."
            }
            guard detection != announcedDetection else { return nil }
            announcedDetection = detection
            return detection.isEmpty ? nil : "Detected: " + detection.joined(separator: ", then ") + "."
        }
    }
}
