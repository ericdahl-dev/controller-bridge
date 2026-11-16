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
        let lsbOf = pairs(voices)
        let msbOf = Dictionary(uniqueKeysWithValues: lsbOf.map { ($1, $0) })
        var order: [ControlKey] = []
        var byControl: [ControlKey: [Voice]] = [:]
        for voice in voices {
            let key = msbOf[voice.control] ?? voice.control
            if byControl[key] == nil { order.append(key) }
            byControl[key, default: []].append(voice)
        }
        return order.compactMap { key in byControl[key].flatMap { facts(key, lsb: lsbOf[key], $0) } }
    }

    private static func facts(_ key: ControlKey, lsb: ControlKey?, _ voices: [Voice]) -> ControlFacts? {
        switch key.kind {
        case .note: noteFacts(key, voices)
        case .cc: ccFacts(key, lsb: lsb, voices)
        case .pitchBend: nil
        }
    }

    /// 14-bit pairs, MSB to LSB: two CCs on one channel whose messages arrive side by side. The MSB is the lower of
    /// n and n+32 (the MIDI convention); otherwise, as on the LC6000's Needle Drop (64 and 65), the one sent first.
    private static func pairs(_ voices: [Voice]) -> [ControlKey: ControlKey] {
        let ccs = voices.filter { $0.kind == .cc }.map(\.control)
        var counts: [ControlKey: Int] = [:]
        for key in ccs { counts[key, default: 0] += 1 }
        var adjacent: [[ControlKey]: Int] = [:]
        var index = 0
        while index + 1 < ccs.count {
            let a = ccs[index], b = ccs[index + 1]
            if a.channel == b.channel, a.number != b.number {
                adjacent[[a, b], default: 0] += 1
                index += 2
            } else {
                index += 1
            }
        }
        var lsbOf: [ControlKey: ControlKey] = [:]
        var taken: Set<ControlKey> = []
        for (keys, count) in adjacent.sorted(by: { $0.value > $1.value }) {
            let a = keys[0], b = keys[1]
            guard !taken.contains(a), !taken.contains(b) else { continue }
            let fewer = min(counts[a] ?? 0, counts[b] ?? 0)
            guard Double(count) >= 0.8 * Double(fewer) else { continue }
            let (msb, lsb) = b.number < 32 && a.number == b.number + 32 ? (b, a) : (a, b)
            lsbOf[msb] = lsb
            taken.formUnion([a, b])
        }
        return lsbOf
    }

    private static func ccFacts(_ key: ControlKey, lsb: ControlKey?, _ voices: [Voice]) -> ControlFacts? {
        var values: [Int] = []
        if let lsb {
            var msbValue: Int?
            for voice in voices {
                if voice.control == lsb, let msb = msbValue {
                    values.append(msb << 7 | voice.value)
                } else if voice.control == key {
                    msbValue = voice.value
                }
            }
        } else {
            values = voices.map(\.value)
        }
        guard let first = values.first, let last = values.last else { return nil }
        return ControlFacts(
            kind: .cc, channel: key.channel + 1, number: key.number, lsb: lsb?.number, encoding: .absolute,
            first: first, last: last, min: values.min() ?? first, max: values.max() ?? first
        )
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
