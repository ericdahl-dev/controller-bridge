import ControllerBridgeCapture
import Foundation
import Testing

/// The capture file (#185): versioned JSON shared by the app and the web capture (#190), so its key names are pinned
/// by a literal here, not only by a round trip (a round trip passes with any key names).
@Suite("Capture file")
struct CaptureFileTests {
    static let literal = """
    {
      "format": 1,
      "app_version": "1.2.0",
      "device": "LC6000 PRIME",
      "ports": { "input": ["LC6000 PRIME", "LC6000 PRIME WD"], "output": ["LC6000 PRIME"] },
      "note": "Firmware 1.3",
      "prompts": [
        { "id": "idle", "text": "Don't touch anything.", "gesture": "idle" },
        { "id": "deck1.play", "text": "Press Play on deck 1.", "gesture": "press" },
        { "id": "deck1.play.shift", "text": "Hold Shift and press Play.", "gesture": "press", "shifted_of": "deck1.play" },
        { "id": "deck1.pitch", "text": "Move the pitch fader from the bottom to the top.", "gesture": "move" }
      ],
      "noise": ["90 34"],
      "steps": [
        {
          "prompt": "deck1.play",
          "status": "confirmed",
          "messages": [{ "t": 0, "midi": "90 01 7F" }, { "t": 120, "midi": "80 01 00" }],
          "controls": [
            { "kind": "note", "channel": 1, "number": 1, "release": "note_off", "first": 127, "last": 127, "min": 127, "max": 127 }
          ],
          "leds": [{ "sent": "90 01 7F", "lit": true, "color": "red" }]
        },
        {
          "prompt": "deck1.play.shift",
          "status": "skipped",
          "messages": [],
          "controls": [],
          "leds": []
        },
        {
          "prompt": "deck1.pitch",
          "status": "confirmed",
          "messages": [{ "t": 0, "midi": "B0 08 7F" }, { "t": 1, "midi": "B0 28 7F" }],
          "controls": [
            { "kind": "cc", "channel": 1, "number": 8, "lsb": 40, "encoding": "absolute", "first": 16383, "last": 0, "min": 0, "max": 16383 }
          ],
          "leds": [],
          "shift": { "of": "deck1.play", "channel_offset": 0, "number_offset": 0 }
        }
      ]
    }
    """

    static let file = CaptureFile(
        appVersion: "1.2.0",
        device: "LC6000 PRIME",
        ports: CapturePorts(input: ["LC6000 PRIME", "LC6000 PRIME WD"], output: ["LC6000 PRIME"]),
        note: "Firmware 1.3",
        prompts: [
            CapturePrompt(id: "idle", text: "Don't touch anything.", gesture: .idle),
            CapturePrompt(id: "deck1.play", text: "Press Play on deck 1.", gesture: .press),
            CapturePrompt(id: "deck1.play.shift", text: "Hold Shift and press Play.", gesture: .press, shiftedOf: "deck1.play"),
            CapturePrompt(id: "deck1.pitch", text: "Move the pitch fader from the bottom to the top.", gesture: .move),
        ],
        noise: [[0x90, 0x34]],
        steps: [
            CaptureStep(
                prompt: "deck1.play", status: .confirmed,
                messages: [CaptureMessage(t: 0, bytes: [0x90, 0x01, 0x7F]), CaptureMessage(t: 120, bytes: [0x80, 0x01, 0x00])],
                controls: [ControlFacts(kind: .note, channel: 1, number: 1, release: .noteOff, first: 127, last: 127, min: 127, max: 127)],
                leds: [LEDAnswer(sent: [0x90, 0x01, 0x7F], lit: true, color: "red")]
            ),
            CaptureStep(prompt: "deck1.play.shift", status: .skipped),
            CaptureStep(
                prompt: "deck1.pitch", status: .confirmed,
                messages: [CaptureMessage(t: 0, bytes: [0xB0, 0x08, 0x7F]), CaptureMessage(t: 1, bytes: [0xB0, 0x28, 0x7F])],
                controls: [ControlFacts(kind: .cc, channel: 1, number: 8, lsb: 40, encoding: .absolute, first: 16383, last: 0, min: 0, max: 16383)],
                shift: ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 0)
            ),
        ]
    )

    @Test("The literal format-1 file decodes to the model")
    func decodesLiteral() throws {
        let decoded = try CaptureFile.decode(Data(Self.literal.utf8))
        #expect(decoded == Self.file)
    }

    @Test("The model encodes to the same JSON as the literal: snake_case keys, hex MIDI, nil fields left out")
    func encodesLiteral() throws {
        let encoded = try JSONSerialization.jsonObject(with: Self.file.encoded()) as? NSDictionary
        let literal = try JSONSerialization.jsonObject(with: Data(Self.literal.utf8)) as? NSDictionary
        #expect(encoded != nil)
        #expect(encoded == literal)
    }

    @Test("A file from a newer format is refused in plain words, not misread")
    func refusesNewerFormat() {
        let newer = Self.literal.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2")
        #expect(throws: CaptureFileError.unsupportedFormat(2)) { try CaptureFile.decode(Data(newer.utf8)) }
        #expect(CaptureFileError.unsupportedFormat(2).description == "This capture file is format 2; this version reads format 1. Update DeckBridge.")
    }
}
