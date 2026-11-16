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
    /// The controller went away mid-capture (#229): nothing moves on until it's back or the capture is ended.
    public private(set) var isDisconnected = false
    /// A disconnect or reconnect to announce, ahead of anything else.
    private var connectionNote: String?
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
    /// For a shifted step, how Shift changed the control: "Shift: same message", "Shift: channel +1, note +60" (#229).
    /// Nil until the control arrives, and when the step it repeats was skipped.
    public private(set) var shiftReadout: String?
    /// On a layer step (#217): the select step's button and indicator, or a layered step's offset from deck 1.
    public private(set) var layerReadout: String?
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
        guard phase == .steps, !isDisconnected else { return }
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
        shiftReadout = phase == .steps ? session?.currentShift.map { Self.readout($0, kind: detected.first?.kind) } : nil
        let layer = phase == .steps ? session?.currentLayer : nil
        layerReadout = prompt?.layerOf == nil ? layer?.selectReadout : layer?.offsetReadout
        stale = false
        if let time { lastRefresh = time }
    }

    /// Whole seconds left before the idle step's Next, or nil on any other step.
    public func idleSecondsLeft(at now: Double) -> Int? {
        guard prompt?.gesture == .idle else { return nil }
        return max(0, Int((Self.idleSeconds - (now - stepStart)).rounded(.up)))
    }

    public func canNext(at now: Double) -> Bool {
        guard let prompt, !isDisconnected else { return false }
        return prompt.gesture == .idle ? now - stepStart >= Self.idleSeconds : !detected.isEmpty
    }

    public var canRedo: Bool { !isDisconnected && prompt.map { $0.gesture != .idle } == true && session?.hasTake == true }
    public var canSkip: Bool { !isDisconnected && prompt.map { $0.gesture != .idle } == true }

    public mutating func next(at time: Double) {
        guard canNext(at: time) else { return }
        session?.confirm(at: time)
        moved(at: time)
    }

    public mutating func redo(at time: Double) {
        guard prompt != nil, !isDisconnected else { return }
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

    /// Ends the capture now, keeping the steps so far (#229). The rest of the prompts are left out of the file.
    public mutating func endCapture(at time: Double) {
        guard phase == .steps else { return }
        isDisconnected = false
        connectionNote = nil
        phase = .done
        refresh(at: time)
    }

    /// The controller being captured went away (#229).
    public mutating func disconnected(at time: Double) {
        guard phase == .steps, !isDisconnected else { return }
        isDisconnected = true
        connectionNote = "Controller disconnected. Plug it back in to continue, or end the capture."
    }

    /// It's back: the same step starts again, its partial take thrown away.
    public mutating func reconnected(at time: Double) {
        guard isDisconnected else { return }
        isDisconnected = false
        session?.redo(at: time)
        stepStart = time
        refresh(at: time)
        announcedStep = stepNumber
        announcedDetection = []
        connectionNote = "Controller reconnected. Step \(stepNumber) of \(stepCount). \(prompt?.text ?? "")"
    }

    /// What VoiceOver should announce now, if anything: a disconnect or reconnect, a new prompt, a change in what's
    /// detected, or the end. Each is said once; the app calls this after every update.
    public mutating func takeAnnouncement() -> String? {
        if let note = connectionNote {
            connectionNote = nil
            return note
        }
        switch phase {
        case .ports: return nil
        case .done:
            guard !announcedDone else { return nil }
            announcedDone = true
            let steps = file?.steps ?? []
            if steps.count < stepCount { return "Capture ended early: \(steps.count) of \(stepCount) steps." }
            let skipped = steps.filter { $0.status == .skipped }.count
            return "Capture finished: \(steps.count) steps, \(skipped) skipped."
        case .steps:
            let notes = [shiftReadout, layerReadout].compactMap { $0 }
            let detection = detected.map(\.spoken) + notes
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
            guard !detected.isEmpty else { return nil }
            return "Detected: " + detected.map(\.spoken).joined(separator: ", then ") + "." + notes.map { " \($0)." }.joined()
        }
    }

    /// "Shift: same message", or what moved: "Shift: channel +1, note +60" (a CC says CC).
    static func readout(_ shift: ShiftLayer, kind: ControlKind?) -> String {
        func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
        var parts: [String] = []
        if shift.channelOffset != 0 { parts.append("channel \(signed(shift.channelOffset))") }
        if shift.numberOffset != 0 { parts.append("\(kind == .cc ? "CC" : "note") \(signed(shift.numberOffset))") }
        return "Shift: " + (parts.isEmpty ? "same message" : parts.joined(separator: ", "))
    }
}
