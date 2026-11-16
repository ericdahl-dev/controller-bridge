// Pads, pad modes and cue colors (#18), as in the Python bridge.

/// What the eight pads do.
enum PadMode {
    case hotCue, roll, loop, slicer
}

extension Bridge {
    /// Syndicate's default cue colors by slot.
    static let defaultPalette: [Int: [Int]] = [
        1: [255, 0, 0], 2: [255, 128, 0], 3: [255, 255, 0], 4: [0, 255, 0],
        5: [0, 255, 255], 6: [0, 0, 255], 7: [128, 0, 255], 8: [255, 0, 255],
    ]

    /// The color slots from Cues feedback: a slot and a name per cue, 8 cues.
    static func cueSlots(_ arguments: [OSCArgument]) -> [Int] {
        let slots = stride(from: 0, to: arguments.count, by: 2).prefix(8).map { index -> Int in
            if case .int(let slot) = arguments[index] { return Int(slot) }
            return 0
        }
        return slots + Array(repeating: 0, count: 8 - slots.count)
    }

    /// ColorPalette feedback: a slot, then its red, green and blue (0-255).
    func colorPalette(_ arguments: [OSCArgument]) {
        let numbers = arguments.compactMap(\.wholeNumber)
        guard numbers.count >= 4 else { return }
        palette[numbers[0]] = Array(numbers[1...3])
        refreshLEDs()
    }

    /// Slip roll sizes, pad 1 to pad 8.
    static let rollSizes = ["ThirtySecond", "Sixteenth", "Eighth", "Quarter", "Half", "One", "Two", "Four"]

    /// A mode button. Switching mode first releases any held pad, so a hot cue or roll never sticks.
    func padModeButton(_ mode: PadMode) -> (Bool) -> Void {
        { pressed in
            guard pressed else { return }
            self.releasePads()
            self.padMode = mode
            self.refreshLEDs()
        }
    }

    /// Releases every held pad, and nothing else.
    func releasePads() {
        for index in mapping.notes.pads.indices { releaseHold(.pad(index)) }
    }

    /// A pad press or release. `index` is 0-7, so hot cue `index + 1`.
    func handlePad(_ index: Int, pressed: Bool) {
        defer { refreshLEDs() }
        guard pressed else { return releaseHold(.pad(index)) }
        let cue = Int32(index + 1)
        switch padMode {
        case .hotCue: hold(.pad(index), "HotCue", press: [.int(cue), .int(1)], release: [.int(cue), .int(0)])
        case .roll: hold(.pad(index), "SlipLoop/" + Self.rollSizes[index], press: [.int(1)], release: [.int(0)])
        case .loop: sendDeck("SetCueLoop", .int(cue))
        case .slicer: break
        }
    }

    // MARK: LEDs

    func padLEDs() {
        let modes: [(String, PadMode)] = [("mode_hotcue", .hotCue), ("mode_roll", .roll), ("mode_loop", .loop), ("mode_slicer", .slicer)]
        for (name, mode) in modes { buttonLED(name, on: padMode == mode) }
        for (note, velocity) in zip(mapping.notes.pads, padColors()) { led(note, velocity) }
        ringLED()
    }

    /// Hot Cue: each cue in its color. Loop: each cue in the loop color. Roll: every pad in the roll color.
    /// Slicer: off. An empty cue is off.
    func padColors() -> [UInt8] {
        let leds = mapping.leds
        switch padMode {
        case .hotCue:
            return cues.enumerated().map { index, slot in
                guard slot != 0 else { return Self.off }
                let color = palette[slot] ?? [255, 255, 255]
                // A held hot cue shows the brightest version of its color, so you can see which one is sounding.
                return Self.velocity(held.contains(.pad(index)) ? Self.brightest(color) : color)
            }
        case .loop: return cues.map { $0 == 0 ? Self.off : Self.velocity(leds.loopPadColor) }
        case .roll: return Array(repeating: Self.velocity(leds.rollPadColor), count: cues.count)
        case .slicer: return Array(repeating: Self.off, count: cues.count)
        }
    }

    /// The color scaled up so its strongest channel is 255.
    static func brightest(_ rgb: [Int]) -> [Int] {
        guard let top = rgb.max(), top > 0 else { return rgb }
        return rgb.map { $0 * 255 / top }
    }

    /// A pad or ring velocity for an [r, g, b] color.
    static func velocity(_ rgb: [Int]) -> UInt8 {
        // A user mapping can hold any list here until the mapping check (#24) refuses it.
        guard rgb.count == 3 else { return off }
        return rgbToVelocity(rgb[0], rgb[1], rgb[2])
    }
}

private extension OSCArgument {
    /// An int, or a float cut to an int as the Python bridge's int() does. A NaN, an infinity or a float too big
    /// for an Int (feedback is untrusted UDP) gives nil instead of trapping.
    var wholeNumber: Int? {
        switch self {
        case .int(let value): Int(value)
        case .float(let value): Int(exactly: value.rounded(.towardZero))
        case .string: nil
        }
    }
}
