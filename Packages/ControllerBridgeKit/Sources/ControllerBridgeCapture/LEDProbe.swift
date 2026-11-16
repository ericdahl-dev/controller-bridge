// The LED and color probe (#187): what the capture window lights on the controller, and what it asks the owner.

/// One thing to light, and the question about it.
public struct LEDProbe: Equatable, Sendable {
    public enum Question: String, Equatable, Sendable {
        /// Did it light? Yes or no.
        case lit
        /// Lit at a low value: dim, bright or off (for the profile's LED levels).
        case level
        /// What color? (for the profile's color table, at values spread over the range).
        case color
    }

    public enum Scope: Equatable, Sendable {
        /// Transport buttons and pads.
        case quick
        /// Every captured button.
        case full
    }

    /// The prompt id of the step whose control is lit; the answer is kept with that step.
    public var step: String
    public var question: Question
    public var text: String
    /// The message that lights it: a note-on or a CC, nothing else.
    public var message: [UInt8]
    /// The message that turns it off again.
    public var off: [UInt8]

    public init(step: String, question: Question, text: String, message: [UInt8], off: [UInt8]) {
        self.step = step
        self.question = question
        self.text = text
        self.message = message
        self.off = off
    }

    /// The pad color values: spread over 1-127, not one controller's palette (#187).
    public static let colorValues: [UInt8] = [1, 8, 16, 24, 32, 48, 64, 80, 96, 112, 127]
    /// The pad whose colors are probed.
    static let colorStep = "deck1.hotcue1"
    /// The button whose low level is probed.
    static let levelStep = "deck1.play"
    static let quickSteps: Set<String> = ["deck1.play", "deck1.cue", "deck1.sync"]

    /// The probes for the captured steps, in prompt order. Only confirmed press steps whose first control is a note
    /// or a CC, and neither a Shift variant nor a layer step.
    public static func plan(prompts: [CapturePrompt], steps: [CaptureStep], scope: Scope) -> [LEDProbe] {
        prompts.flatMap { prompt -> [LEDProbe] in
            guard prompt.gesture == .press, prompt.shiftedOf == nil, prompt.layer == nil,
                scope == .full || quickSteps.contains(prompt.id) || prompt.id.hasPrefix("deck1.hotcue"),
                let control = steps.last(where: { $0.prompt == prompt.id && $0.status == .confirmed })?.controls.first,
                let number = control.number, control.kind == .note || control.kind == .cc
            else { return [] }
            let status = UInt8(control.kind == .note ? 0x90 : 0xB0) | UInt8((control.channel - 1) & 0x0F)
            func probe(_ question: Question, _ text: String, _ value: UInt8) -> LEDProbe {
                LEDProbe(step: prompt.id, question: question, text: text, message: [status, UInt8(number), value],
                         off: [status, UInt8(number), 0])
            }
            let name = name(of: prompt.id)
            if prompt.id == colorStep {
                return colorValues.map { probe(.color, "What color is \(name) now?", $0) }
            }
            var probes = [probe(.lit, "Did \(name) light up?", 127)]
            if prompt.id == levelStep {
                probes.append(probe(.level, "\(name) is lit at a low value. Is it dim, bright or off?", 1))
            }
            return probes
        }
    }

    /// A control's name in a question: "Play", "pad 3", "Loop In".
    static func name(of id: String) -> String {
        let last = id.split(separator: ".").dropFirst().joined(separator: ".")
        if last.hasPrefix("hotcue") { return "pad \(last.dropFirst("hotcue".count))" }
        return [
            "play": "Play", "cue": "Cue", "sync": "Sync", "loop_in": "Loop In", "loop_out": "Loop Out",
            "auto_loop": "Auto Loop", "browse.press": "the browse knob", "shift": "Shift",
        ][last] ?? "that control"
    }
}
