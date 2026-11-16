import ControllerBridgeCapture
import Testing

/// The demo controller in the capture window (#186): a fixed LC6000-like script per prompt, fed through the same flow
/// as real MIDI, so the window can be tried and reviewed without hardware.
@Suite("Demo capture")
struct DemoCaptureTests {
    /// Walks the whole standard list on demo traffic, a step every 10 seconds.
    static func walked(ledTest: Bool = false) -> (flow: CaptureFlow, detectedEachStep: [Bool]) {
        var flow = CaptureFlow(appVersion: "1.2.0", ledTest: ledTest)
        flow.start(device: DemoCapture.deviceName, ports: DemoCapture.ports, at: 0)
        var detectedEachStep: [Bool] = []
        var now = 0.0
        while let prompt = flow.prompt {
            for message in DemoCapture.take(for: prompt) { flow.receive(message.bytes, at: now + 1 + message.time) }
            now += 6
            detectedEachStep.append(prompt.gesture == .idle || !flow.detected.isEmpty)
            flow.next(at: now)
            now += 4
        }
        return (flow, detectedEachStep)
    }

    @Test("Every step of the standard list detects something, so Next works all the way to done")
    func everyStep() {
        let (flow, detected) = Self.walked()
        #expect(flow.phase == .done)
        #expect(detected.count == CapturePrompts.djController.count)
        #expect(!detected.contains(false))
        #expect(flow.file?.steps.allSatisfy { $0.status == .confirmed } == true)
    }

    @Test("The demo answers like an LC6000: Play note 1, jog CC 17/49, pitch 8/40 with up 0, browse two's complement")
    func knownAnswers() throws {
        let steps = try #require(Self.walked().flow.file?.steps)
        func controls(_ id: String) -> [String] { steps.first { $0.prompt == id }?.controls.map(\.summary) ?? [] }
        #expect(controls("deck1.play") == ["Note 1 on ch 1"])
        #expect(controls("deck1.jog.touch") == ["Note 40 on ch 1", "CC 17 + 49 on ch 1, 14-bit, absolute"])
        #expect(controls("deck1.needle") == ["Note 70 on ch 1", "CC 64 + 65 on ch 1, 14-bit, absolute"])
        #expect(controls("deck1.browse.turn") == ["CC 6 on ch 1, relative (two's complement)"])
        #expect(controls("deck2.play") == ["Note 1 on ch 2"])
        let pitch = steps.first { $0.prompt == "deck1.pitch" }?.controls.first
        #expect(pitch?.first == 0)
        #expect(pitch?.last == 16383)
        #expect(steps.first { $0.prompt == "deck1.play.shift" }?.shift == ShiftLayer(of: "deck1.play", channelOffset: 0, numberOffset: 0))
        #expect(Self.walked().flow.file?.noise == [[0x90, 0x34]])
        // The standard list's layer steps (#217).
        let layers = Self.walked().flow.file?.layers ?? []
        #expect(layers.map(\.selectReadout) == ["Layer 2: Shift + Note 55 on ch 16 · indicator Note 51 on ch 2"])
        #expect(layers.map(\.offsetReadout) == ["Layer 2: channel +1"])
    }

    @Test("The demo's layer step is the LC6000's: Shift + note 55 on ch 16, note 51 on ch 2, and deck 2 on channel +1 (#217)")
    func layers() {
        let prompts = [
            CapturePrompt(id: "deck1.play", text: "Play.", gesture: .press),
            CapturePrompt(id: "layer2.select", text: "Deck 2.", gesture: .press, layer: 2),
            CapturePrompt(id: "deck2.play", text: "Play on deck 2.", gesture: .press, layer: 2, layerOf: "deck1.play"),
        ]
        var flow = CaptureFlow(prompts: prompts, appVersion: "1.2.0")
        flow.start(device: DemoCapture.deviceName, ports: DemoCapture.ports, at: 0)
        var now = 0.0
        while let prompt = flow.prompt {
            for message in DemoCapture.take(for: prompt) { flow.receive(message.bytes, at: now + 1 + message.time) }
            now += 10
            flow.next(at: now)
        }
        #expect(flow.file?.layers.first?.select?.summary == "Note 55 on ch 16")
        #expect(flow.file?.layers.first?.withShift == true)
        #expect(flow.file?.layers.first?.indicator?.summary == "Note 51 on ch 2")
        #expect(flow.file?.layers.first?.channelOffset == 1)
    }

    @Test("Demo end to end with the LED test (#187): every probe is answered, sent as note or CC, and all off at the end")
    func ledTest() throws {
        var flow = Self.walked(ledTest: true).flow
        flow.startLEDs(scope: .full, at: 1000)
        var sent: [[UInt8]] = []
        var now = 1000.0
        while flow.phase == .leds {
            sent += flow.dueSends(at: now)
            guard flow.canAnswerLED else { now += 0.1; continue }
            let choice: CaptureFlow.LEDChoice = switch flow.ledProbe?.question {
            case .lit: .lit(true)
            case .level: .level(.dim)
            default: .color("red")
            }
            flow.answerLED(choice, at: now)
            now += 0.1
        }
        while flow.hasPendingSends {
            sent += flow.dueSends(at: now)
            now += 0.1
        }
        let file = try #require(flow.file)
        // Play, Cue, Sync, pads 2-8, Loop In, Loop Out, Auto Loop, browse press, Shift: 15 lit; Play's level; 11 pad 1 colors.
        #expect(flow.ledAnswerCount == 27)
        #expect(file.summary.contains("27 LED answers"))
        #expect(sent.allSatisfy { [0x90, 0xB0].contains($0[0] & 0xF0) })
        // Each control lit is turned off again by the end.
        var lit: Set<[UInt8]> = []
        for message in sent { if message[2] == 0 { lit.remove(Array(message[0...1])) } else { lit.insert(Array(message[0...1])) } }
        #expect(lit.isEmpty)
    }
}
