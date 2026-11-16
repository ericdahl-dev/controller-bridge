import ControllerBridgeCapture
import Testing

/// The LED and color probe (#187): what the capture window lights, and what it asks, from the captured steps.
@Suite("LED probe")
struct LEDProbeTests {
    static func note(_ number: Int, channel: Int = 1) -> ControlFacts {
        ControlFacts(kind: .note, channel: channel, number: number, release: .noteOff, first: 127, last: 127, min: 127, max: 127)
    }

    static let prompts = [
        CapturePrompt(id: "idle", text: "Hands off.", gesture: .idle),
        CapturePrompt(id: "deck1.play", text: "Play.", gesture: .press),
        CapturePrompt(id: "deck1.sync", text: "Sync.", gesture: .press),
        CapturePrompt(id: "deck1.hotcue1", text: "Pad 1.", gesture: .press),
        CapturePrompt(id: "deck1.loop_in", text: "Loop In.", gesture: .press),
        CapturePrompt(id: "deck1.pitch", text: "Pitch.", gesture: .move),
        CapturePrompt(id: "deck1.play.shift", text: "Shift Play.", gesture: .press, shiftedOf: "deck1.play"),
        CapturePrompt(id: "deck1.cue", text: "Cue.", gesture: .press),
    ]

    static let steps = [
        CaptureStep(prompt: "idle", status: .confirmed),
        CaptureStep(prompt: "deck1.play", status: .confirmed, controls: [note(1)]),
        CaptureStep(prompt: "deck1.sync", status: .confirmed, controls: [
            ControlFacts(kind: .cc, channel: 2, number: 20, encoding: .absolute, first: 127, last: 0, min: 0, max: 127),
        ]),
        CaptureStep(prompt: "deck1.hotcue1", status: .confirmed, controls: [note(32)]),
        CaptureStep(prompt: "deck1.loop_in", status: .confirmed, controls: [note(8)]),
        CaptureStep(prompt: "deck1.pitch", status: .confirmed, controls: [
            ControlFacts(kind: .cc, channel: 1, number: 8, lsb: 40, encoding: .absolute, first: 0, last: 16383, min: 0, max: 16383),
        ]),
        CaptureStep(prompt: "deck1.play.shift", status: .confirmed, controls: [note(1)]),
        CaptureStep(prompt: "deck1.cue", status: .skipped),
    ]

    @Test("Full: every captured button gets a lit question; Play also a level; pad 1 a color at 11 values from 1 to 127")
    func full() {
        let plan = LEDProbe.plan(prompts: Self.prompts, steps: Self.steps, scope: .full)
        #expect(plan.map(\.text) == [
            "Did Play light up?",
            "Play is lit at a low value. Is it dim, bright or off?",
            "Did Sync light up?",
        ] + Array(repeating: "What color is pad 1 now?", count: 11) + [
            "Did Loop In light up?",
        ])
        #expect(plan[0] == LEDProbe(step: "deck1.play", question: .lit, text: "Did Play light up?",
                                    message: [0x90, 1, 127], off: [0x90, 1, 0]))
        #expect(plan[1].message == [0x90, 1, 1])
        #expect(plan[2].message == [0xB1, 20, 127])
        #expect(plan[2].off == [0xB1, 20, 0])
        #expect(plan[3...13].map { $0.message[2] } == [1, 8, 16, 24, 32, 48, 64, 80, 96, 112, 127])
        #expect(plan[3...13].allSatisfy { $0.step == "deck1.hotcue1" && $0.question == .color })
    }

    @Test("Quick: transport and pads only")
    func quick() {
        let plan = LEDProbe.plan(prompts: Self.prompts, steps: Self.steps, scope: .quick)
        #expect(Set(plan.map(\.step)) == ["deck1.play", "deck1.sync", "deck1.hotcue1"])
    }

    @Test("Never probed: faders, knobs, the jog, Shift variants, layer steps and skipped steps; and only note and CC messages")
    func neverProbed() {
        let plan = LEDProbe.plan(prompts: Self.prompts, steps: Self.steps, scope: .full)
        #expect(!plan.contains { ["deck1.pitch", "deck1.play.shift", "deck1.cue", "idle"].contains($0.step) })
        #expect(plan.allSatisfy { [0x90, 0xB0].contains($0.message[0] & 0xF0) && $0.message.count == 3 })
    }
}
