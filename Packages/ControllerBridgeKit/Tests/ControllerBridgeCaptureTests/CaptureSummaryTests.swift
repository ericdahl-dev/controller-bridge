import ControllerBridgeCapture
import Testing

/// What the owner sees before saving or emailing a capture (#188): a plain list of everything the file holds.
@Suite("Capture summary")
struct CaptureSummaryTests {
    static func file(note: String? = nil, leds: [LEDAnswer] = []) -> CaptureFile {
        CaptureFile(
            appVersion: "1.2.0", device: "LC6000 PRIME",
            ports: CapturePorts(input: ["LC6000 PRIME", "LC6000 PRIME WD"], output: ["LC6000 PRIME"]),
            note: note,
            prompts: [],
            steps: [
                CaptureStep(prompt: "idle", status: .confirmed, messages: [CaptureMessage(t: 0, bytes: [0x90, 0x34, 0x7F])]),
                CaptureStep(
                    prompt: "deck1.play", status: .confirmed,
                    messages: [CaptureMessage(t: 0, bytes: [0x90, 0x01, 0x7F]), CaptureMessage(t: 120, bytes: [0x80, 0x01, 0x00])],
                    leds: leds
                ),
                CaptureStep(prompt: "deck1.cue", status: .skipped),
            ]
        )
    }

    @Test("Every line of what's in the file, ending with what isn't")
    func summary() {
        #expect(Self.file().summary == [
            "Controller: LC6000 PRIME",
            "Ports: LC6000 PRIME, LC6000 PRIME WD (in); LC6000 PRIME (out)",
            "3 steps: 2 captured, 1 skipped",
            "3 MIDI messages, as the controller sent them",
            "No note",
            "DeckBridge 1.2.0",
            "Nothing else: no name, email, location or time of day.",
        ])
    }

    @Test("The owner's note and any LED answers are listed too; one message reads as one")
    func noteAndLEDs() {
        var file = Self.file(note: "Firmware 1.3", leds: [LEDAnswer(sent: [0x90, 0x01, 0x7F], lit: true, color: "red")])
        file.steps = [file.steps[1]]
        file.steps[0].messages = [file.steps[0].messages[0]]
        #expect(file.summary == [
            "Controller: LC6000 PRIME",
            "Ports: LC6000 PRIME, LC6000 PRIME WD (in); LC6000 PRIME (out)",
            "1 step: 1 captured, 0 skipped",
            "1 MIDI message, as the controller sent it",
            "1 LED answer",
            "Your note: Firmware 1.3",
            "DeckBridge 1.2.0",
            "Nothing else: no name, email, location or time of day.",
        ])
    }

    @Test("The file name and email name the controller, with characters a file name can't hold made safe")
    func namesAndEmail() {
        var file = Self.file()
        #expect(file.suggestedFileName == "LC6000 PRIME capture.deckbridge-capture")
        #expect(file.emailSubject == "Controller capture: LC6000 PRIME")
        #expect(CaptureFile.emailRecipient == "deckbridge@ericdahl.dev")
        #expect(file.emailBody == "Here's a capture of my LC6000 PRIME for DeckBridge. The file is attached.")
        file.device = "DJ/Con:troller 4"
        #expect(file.suggestedFileName == "DJ-Con-troller 4 capture.deckbridge-capture")
        file.device = "  "
        #expect(file.suggestedFileName == "Controller capture.deckbridge-capture")
    }
}
