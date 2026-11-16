// Deck layer variants (#217): read from the finished steps, so the app's session and a re-inferred web file
// (CaptureFile.inferred, #190) get the same answer.

/// What a capture says about one deck layer.
public struct LayerFacts: Codable, Equatable, Sendable {
    public var layer: Int
    /// The button that switches to the layer; nil when its step was skipped or caught nothing.
    public var select: ControlFacts?
    /// Whether Shift was held for it, as the LC6000's Shift + deck select.
    public var withShift: Bool
    /// What the controller sends to mark the layer active, unasked, such as the LC6000's note 51 at 127 on ch 2.
    public var indicator: ControlFacts?
    /// How the layer's controls differ from deck 1's: from a layered step against the step it repeats. Nil when
    /// either was skipped.
    public var channelOffset: Int?
    public var numberOffset: Int?

    public init(
        layer: Int, select: ControlFacts?, withShift: Bool, indicator: ControlFacts?, channelOffset: Int?, numberOffset: Int?
    ) {
        self.layer = layer
        self.select = select
        self.withShift = withShift
        self.indicator = indicator
        self.channelOffset = channelOffset
        self.numberOffset = numberOffset
    }

    enum CodingKeys: String, CodingKey {
        case layer, select, withShift = "with_shift", indicator, channelOffset = "channel_offset", numberOffset = "number_offset"
    }
}

public enum CaptureLayers {
    /// One entry per layer a prompt selects, in prompt order.
    public static func infer(prompts: [CapturePrompt], steps: [CaptureStep]) -> [LayerFacts] {
        func confirmed(_ id: String) -> CaptureStep? { steps.last { $0.prompt == id && $0.status == .confirmed } }
        return prompts.filter { $0.layer != nil && $0.layerOf == nil }.compactMap { selectPrompt in
            guard let layer = selectPrompt.layer else { return nil }
            var facts = LayerFacts(layer: layer, select: nil, withShift: false, indicator: nil, channelOffset: nil, numberOffset: nil)
            if let step = confirmed(selectPrompt.id) { read(step, into: &facts) }
            for layered in prompts where layered.layer == layer {
                guard let base = layered.layerOf, let control = confirmed(layered.id)?.controls.first,
                    let unlayered = confirmed(base)?.controls.first, control.kind == unlayered.kind
                else { continue }
                facts.channelOffset = control.channel - unlayered.channel
                facts.numberOffset = (control.number ?? 0) - (unlayered.number ?? 0)
                break
            }
            return facts
        }
    }

    /// The select button (after any held Shift) and the indicator: a control that turned on without being pressed and
    /// let go.
    private static func read(_ step: CaptureStep, into facts: inout LayerFacts) {
        var controls = step.controls
        let messages = step.messages.filter { !$0.tail }.map { (port: $0.port, bytes: $0.bytes) }
        if let held = Inference.heldAround(messages) {
            facts.withShift = true
            controls.removeAll { $0.kind == .note && $0.port == held.port && $0.channel == held.channel + 1 && $0.number == held.number }
        }
        guard let select = controls.first else { return }
        facts.select = select
        facts.indicator = controls.dropFirst().first { $0.kind != .note || $0.release == nil }
    }
}
