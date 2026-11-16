import ControllerBridgeCapture
import Testing

/// The demo controller in the capture window (#186): a fixed LC6000-like script per prompt, fed through the same flow
/// as real MIDI, so the window can be tried and reviewed without hardware.
@Suite("Demo capture")
struct DemoCaptureTests {
    /// Walks the whole standard list on demo traffic, a step every 10 seconds.
    static func walked() -> (flow: CaptureFlow, detectedEachStep: [Bool]) {
        var flow = CaptureFlow(appVersion: "1.2.0")
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
}
