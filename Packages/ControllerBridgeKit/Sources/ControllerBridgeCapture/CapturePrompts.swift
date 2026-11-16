/// Prompt lists for a guided capture (#186). Their ids are a contract with the draft-profile tool (#189) and the web
/// capture (#190): rename one and both must follow.
public enum CapturePrompts {
    /// A DJ controller, deck 1 in full plus the deck 2 layer. The idle step comes first, so noise is learned before
    /// any control is pressed.
    public static let djController: [CapturePrompt] = [
        CapturePrompt(id: "idle", text: "Don't touch anything for 5 seconds.", gesture: .idle),
        press("deck1.play", "Press and release Play on deck 1."),
        press("deck1.cue", "Press and release Cue on deck 1."),
        press("deck1.sync", "Press and release Sync on deck 1."),
    ] + (1...8).map { press("deck1.hotcue\($0)", "In Hot Cue mode, press and release pad \($0) on deck 1.") } + [
        CapturePrompt(id: "deck1.pitch", text: "Move the pitch fader slowly all the way from the top to the bottom.", gesture: .move),
        CapturePrompt(
            id: "deck1.jog.touch", text: "Touch the top of the jog wheel, turn it right a quarter turn, then left, then let go.",
            gesture: .turn
        ),
        CapturePrompt(id: "deck1.jog.edge", text: "Without touching the top, spin the jog wheel's edge right, then left.", gesture: .turn),
        CapturePrompt(id: "deck1.needle", text: "Touch the needle strip at the left, slide slowly to the right, then let go.", gesture: .move),
        press("deck1.loop_in", "Press and release Loop In on deck 1."),
        press("deck1.loop_out", "Press and release Loop Out on deck 1."),
        press("deck1.auto_loop", "Press and release Auto Loop on deck 1."),
        CapturePrompt(id: "deck1.browse.turn", text: "Turn the browse knob right three clicks, then left three clicks.", gesture: .turn),
        press("deck1.browse.press", "Press and release the browse knob."),
        press("deck1.shift", "Press and release Shift on deck 1."),
        CapturePrompt(id: "deck1.play.shift", text: "Hold Shift, press and release Play, then let go of Shift.", gesture: .press, shiftedOf: "deck1.play"),
        CapturePrompt(id: "deck1.cue.shift", text: "Hold Shift, press and release Cue, then let go of Shift.", gesture: .press, shiftedOf: "deck1.cue"),
        CapturePrompt(
            id: "deck1.hotcue1.shift", text: "Hold Shift, press and release pad 1, then let go of Shift.", gesture: .press,
            shiftedOf: "deck1.hotcue1"
        ),
        press("layer2.select", "Switch the left side to deck 2 (its deck or layer button)."),
        press("deck2.play", "Press and release Play on deck 2."),
    ]

    private static func press(_ id: String, _ text: String) -> CapturePrompt {
        CapturePrompt(id: id, text: text, gesture: .press)
    }
}
