/// One guided capture (#185): it walks the prompt list, credits each message to the current step, and moves on when
/// the owner confirms, redoes or skips. The app and the tests feed it raw MIDI bytes, so it needs no CoreMIDI.
public struct CaptureSession: Sendable {
    public let appVersion: String
    public let device: String
    public let ports: CapturePorts
    public let prompts: [CapturePrompt]
    /// The owner's optional note, the only free text in the file.
    public var note: String?

    private var index = 0
    private var steps: [CaptureStep] = []
    /// The current take: each message with the host time it arrived, in seconds.
    private var take: [(time: Double, bytes: [UInt8])] = []

    public init(appVersion: String, device: String, ports: CapturePorts, prompts: [CapturePrompt]) {
        self.appVersion = appVersion
        self.device = device
        self.ports = ports
        self.prompts = prompts
    }

    /// The prompt being captured, or nil when the list is done.
    public var current: CapturePrompt? { prompts.indices.contains(index) ? prompts[index] : nil }

    /// One raw MIDI message, at any host clock in seconds. Ignored once the list is done.
    public mutating func receive(_ bytes: [UInt8], at time: Double) {
        guard current != nil else { return }
        take.append((time, bytes))
    }

    /// Keeps the current take and moves to the next prompt.
    public mutating func confirm() { finish(.confirmed) }

    /// Throws the current take away and listens again.
    public mutating func redo() { take = [] }

    /// Records the prompt as skipped, with nothing captured, and moves on.
    public mutating func skip() {
        take = []
        finish(.skipped)
    }

    /// The capture so far.
    public var file: CaptureFile {
        CaptureFile(appVersion: appVersion, device: device, ports: ports, note: note, prompts: prompts, steps: steps)
    }

    private var messages: [CaptureMessage] {
        guard let start = take.first?.time else { return [] }
        return take.map { CaptureMessage(t: Int(((($0.time - start) * 1000)).rounded()), bytes: $0.bytes) }
    }

    private mutating func finish(_ status: StepStatus) {
        guard let prompt = current else { return }
        steps.append(CaptureStep(prompt: prompt.id, status: status, messages: messages))
        take = []
        index += 1
    }
}
