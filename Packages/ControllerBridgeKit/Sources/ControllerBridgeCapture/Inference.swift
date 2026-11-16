// What a step's raw messages say about the controls behind them (#185).

/// One channel voice message, cut down to what inference needs. Channels are 0-based here.
struct Voice {
    enum Kind { case noteOn, noteOff, cc }
    var kind: Kind
    var channel: Int
    var number: Int
    var value: Int

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 3 else { return nil }
        channel = Int(bytes[0] & 0x0F)
        number = Int(bytes[1] & 0x7F)
        value = Int(bytes[2] & 0x7F)
        switch bytes[0] & 0xF0 {
        case 0x80: kind = .noteOff
        case 0x90: kind = .noteOn
        case 0xB0: kind = .cc
        default: return nil
        }
    }

    /// Which control sent it: note-on and note-off of one note are the same control.
    var control: ControlKey { ControlKey(kind: kind == .cc ? .cc : .note, channel: channel, number: number) }
}

struct ControlKey: Hashable {
    var kind: ControlKind
    var channel: Int
    var number: Int
}

enum Inference {
    /// The controls in one step, in the order they first appear.
    static func controls(in messages: [[UInt8]]) -> [ControlFacts] {
        let voices = messages.compactMap(Voice.init)
        var order: [ControlKey] = []
        var byControl: [ControlKey: [Voice]] = [:]
        for voice in voices {
            if byControl[voice.control] == nil { order.append(voice.control) }
            byControl[voice.control, default: []].append(voice)
        }
        return order.compactMap { key in byControl[key].flatMap { facts(key, $0) } }
    }

    private static func facts(_ key: ControlKey, _ voices: [Voice]) -> ControlFacts? {
        switch key.kind {
        case .note: noteFacts(key, voices)
        case .cc, .pitchBend: nil
        }
    }

    private static func noteFacts(_ key: ControlKey, _ voices: [Voice]) -> ControlFacts? {
        let presses = voices.filter { $0.kind == .noteOn && $0.value > 0 }.map(\.value)
        guard let first = presses.first, let last = presses.last else { return nil }
        let release: NoteRelease? =
            voices.contains { $0.kind == .noteOff } ? .noteOff
            : voices.contains { $0.kind == .noteOn && $0.value == 0 } ? .noteOnZero : nil
        return ControlFacts(
            kind: .note, channel: key.channel + 1, number: key.number, release: release,
            first: first, last: last, min: presses.min() ?? first, max: presses.max() ?? first
        )
    }
}
