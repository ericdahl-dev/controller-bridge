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
    public var stepNumber: Int { (session?.file.steps.count ?? 0) + 1 }
    public var stepCount: Int { prompts.count }

    /// What the current step has detected so far.
    public var detected: [ControlFacts] { phase == .steps ? session?.currentControls ?? [] : [] }

    /// The capture file, once the steps start.
    public var file: CaptureFile? { session?.file }

    public mutating func receive(_ bytes: [UInt8], at time: Double, port: Int = 0) {
        guard phase == .steps else { return }
        session?.receive(bytes, at: time, port: port)
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
    }

    public mutating func skip(at time: Double) {
        guard canSkip else { return }
        session?.skip(at: time)
        moved(at: time)
    }

    private mutating func moved(at time: Double) {
        stepStart = time
        if session?.current == nil { phase = .done }
    }
}
