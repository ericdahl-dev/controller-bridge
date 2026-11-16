/// One guided capture (#185): it walks the prompt list, credits each message to the current step, and moves on when
/// the owner confirms, redoes or skips. The app and the tests feed it raw MIDI bytes, so it needs no CoreMIDI.
///
/// Noise, such as the LC6000's note 52 heartbeat in host mode, isn't credited to a step. The prompt list starts with
/// an `idle` prompt (hands off), and what arrives then is noise from that point on. When the capture ends, a message
/// that came in every confirmed step is noise too.
public struct CaptureSession: Sendable {
    public let appVersion: String
    public let device: String
    public let ports: CapturePorts
    public let prompts: [CapturePrompt]
    /// The owner's optional note, the only free text in the file.
    public var note: String?

    private typealias Take = [(time: Double, bytes: [UInt8])]

    private var index = 0
    private var finished: [(prompt: CapturePrompt, status: StepStatus, take: Take, leds: [LEDAnswer])] = []
    /// The current take: each message with the host time it arrived, in seconds.
    private var take: Take = []
    private var leds: [LEDAnswer] = []

    public init(appVersion: String, device: String, ports: CapturePorts, prompts: [CapturePrompt]) {
        self.appVersion = appVersion
        self.device = device
        self.ports = ports
        self.prompts = prompts
    }

    /// The prompt being captured, or nil when the list is done.
    public var current: CapturePrompt? { prompts.indices.contains(index) ? prompts[index] : nil }

    /// What the current take has detected so far, for showing live.
    public var currentControls: [ControlFacts] {
        guard let current else { return [] }
        return step(current, .confirmed, take, noise: Set(idleNoise), before: []).controls
    }

    /// One raw MIDI message, at any host clock in seconds. Ignored once the list is done.
    public mutating func receive(_ bytes: [UInt8], at time: Double) {
        guard current != nil else { return }
        take.append((time, bytes))
    }

    /// The owner's answer to one LED probe message during the current step. The probe itself (what's safe to send)
    /// lives in the app; the session only keeps the answers.
    public mutating func answerLED(_ answer: LEDAnswer) {
        guard current != nil else { return }
        leds.append(answer)
    }

    /// Keeps the current take and moves to the next prompt.
    public mutating func confirm() { finish(.confirmed) }

    /// Throws the current take away and listens again.
    public mutating func redo() {
        take = []
        leds = []
    }

    /// Records the prompt as skipped, with nothing captured, and moves on.
    public mutating func skip() {
        take = []
        leds = []
        finish(.skipped)
    }

    /// The capture so far.
    public var file: CaptureFile {
        let noise = idleNoise + repeatedNoise.filter { !idleNoise.contains($0) }
        var steps: [CaptureStep] = []
        for recorded in finished {
            var recordedStep = step(recorded.prompt, recorded.status, recorded.take, noise: Set(noise), before: steps)
            recordedStep.leds = recorded.leds
            steps.append(recordedStep)
        }
        return CaptureFile(
            appVersion: appVersion, device: device, ports: ports, note: note, prompts: prompts, noise: noise, steps: steps
        )
    }

    /// Noise keys heard during confirmed idle steps, in the order first heard.
    private var idleNoise: [[UInt8]] {
        unique(finished.filter { $0.status == .confirmed && $0.prompt.gesture == .idle }.flatMap { $0.take.compactMap { Inference.noiseKey($0.bytes) } })
    }

    /// Noise keys heard in every confirmed step (two at least, or nothing can be said to repeat). A step repeated
    /// with Shift held doesn't count: it repeats its control on purpose.
    private var repeatedNoise: [[UInt8]] {
        let takes = finished.filter { $0.status == .confirmed && $0.prompt.gesture != .idle && $0.prompt.shiftedOf == nil }.map(\.take)
        guard takes.count >= 2 else { return [] }
        let keys = takes.map { Set($0.compactMap { Inference.noiseKey($0.bytes) }) }
        let everywhere = keys.dropFirst().reduce(keys[0]) { $0.intersection($1) }
        return unique(takes[0].compactMap { Inference.noiseKey($0.bytes) }).filter(everywhere.contains)
    }

    private func unique(_ keys: [[UInt8]]) -> [[UInt8]] {
        var seen: Set<[UInt8]> = []
        return keys.filter { seen.insert($0).inserted }
    }

    /// A step as the file shows it: noise left out, the controls inferred, and the Shift layer against `before`.
    private func step(_ prompt: CapturePrompt, _ status: StepStatus, _ take: Take, noise: Set<[UInt8]>, before: [CaptureStep]) -> CaptureStep {
        let kept = prompt.gesture == .idle ? take : take.filter { Inference.noiseKey($0.bytes).map { !noise.contains($0) } ?? true }
        let bytes = kept.map(\.bytes)
        var controls = prompt.gesture == .idle ? [] : Inference.controls(in: bytes, gesture: prompt.gesture)
        var shift: ShiftLayer?
        if let base = prompt.shiftedOf {
            if let held = Inference.heldAround(bytes) {
                controls.removeAll { $0.kind == .note && $0.channel == held.channel && $0.number == held.number }
            }
            shift = shiftLayer(of: base, controls.first, before: before)
        }
        return CaptureStep(prompt: prompt.id, status: status, messages: messages(kept), controls: controls, shift: shift)
    }

    private func messages(_ take: Take) -> [CaptureMessage] {
        guard let start = take.first?.time else { return [] }
        return take.map { CaptureMessage(t: Int((($0.time - start) * 1000).rounded()), bytes: $0.bytes) }
    }

    /// How a shifted control differs from the same control in the confirmed unshifted step.
    private func shiftLayer(of base: String, _ control: ControlFacts?, before: [CaptureStep]) -> ShiftLayer? {
        guard let control,
            let unshifted = before.last(where: { $0.prompt == base && $0.status == .confirmed })?.controls.first,
            unshifted.kind == control.kind
        else { return nil }
        return ShiftLayer(
            of: base, channelOffset: control.channel - unshifted.channel,
            numberOffset: (control.number ?? 0) - (unshifted.number ?? 0)
        )
    }

    private mutating func finish(_ status: StepStatus) {
        guard let prompt = current else { return }
        finished.append((prompt, status, take, leds))
        take = []
        leds = []
        index += 1
    }
}
