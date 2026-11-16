// Pads, pad modes and cue colors (#18), as in the Python bridge.

/// What the pads do.
enum PadMode {
    case hotCue, roll, loop, slicer
}

extension Bridge {
    /// Syndicate's default cue colors by slot.
    static let defaultPalette: [Int: [Int]] = [
        1: [255, 0, 0], 2: [255, 128, 0], 3: [255, 255, 0], 4: [0, 255, 0],
        5: [0, 255, 255], 6: [0, 0, 255], 7: [128, 0, 255], 8: [255, 0, 255],
    ]

    /// The color slots from Cues feedback: a slot and a name per cue, one per pad (#196). Syndicate sends 8; pads past
    /// what it sends are empty.
    static func cueSlots(_ arguments: [OSCArgument], pads: Int) -> [Int] {
        let slots = stride(from: 0, to: arguments.count, by: 2).prefix(pads).map { index -> Int in
            if case .int(let slot) = arguments[index] { return Int(slot) }
            return 0
        }
        return slots + Array(repeating: 0, count: max(0, pads - slots.count))
    }

    /// ColorPalette feedback: a slot, then its red, green and blue (0-255). Syndicate may send several slots in one
    /// message, as OSC arrays, flattened to groups of four.
    func colorPalette(_ arguments: [OSCArgument]) {
        let numbers = arguments.compactMap(\.wholeNumber)
        guard numbers.count >= 4 else { return }
        for start in stride(from: 0, through: numbers.count - 4, by: 4) {
            palette[numbers[start]] = Array(numbers[(start + 1)...(start + 3)])
        }
        refreshLEDs()
    }


    /// A mode button. Switching mode first releases any held pad, so a hot cue or roll never sticks.
    func padModeButton(_ mode: PadMode) -> (Bool) -> Void {
        { pressed in
            guard pressed else { return }
            self.releasePads()
            self.padMode = mode
            self.refreshLEDs()
        }
    }

    /// The pad a note plays, and on a profile with notes per mode (#225) the mode that note belongs to.
    func pad(for note: Int) -> (index: Int, mode: PadMode?)? {
        guard let modeNotes = mapping.pads.modeNotes else {
            return mapping.notes.pads.firstIndex(of: note).map { ($0, nil) }
        }
        let lists: [(PadMode, [Int])] = [(.hotCue, modeNotes.hotcue), (.roll, modeNotes.roll), (.loop, modeNotes.loop),
                                         (.slicer, modeNotes.slicer)]
        for (mode, notes) in lists { if let index = notes.firstIndex(of: note) { return (index, mode) } }
        return nil
    }

    /// A pad note in. A note from another mode's list (#225) switches to that mode first, letting held pads go, as
    /// a mode button does.
    func padNote(_ note: Int, pressed: Bool) -> Bool {
        guard let (index, mode) = pad(for: note) else { return false }
        if let mode, mode != padMode, pressed {
            releasePads()
            padMode = mode
        }
        handlePad(index, pressed: pressed)
        return true
    }

    /// Releases every held pad, and nothing else.
    func releasePads() {
        for index in mapping.notes.pads.indices { releaseHold(.pad(index)) }
    }

    /// A pad press or release. `index` is 0-based, so hot cue `index + 1`.
    func handlePad(_ index: Int, pressed: Bool) {
        defer { refreshLEDs() }
        guard pressed else { return releaseHold(.pad(index)) }
        let cue = Int32(index + 1)
        switch padMode {
        case .hotCue: hold(.pad(index), "HotCue", press: [.int(cue), .int(1)], release: [.int(cue), .int(0)])
        case .roll:
            // The profile's roll sizes (#196); a pad past the list does nothing.
            let sizes = mapping.pads.rollSizes
            guard sizes.indices.contains(index) else { return }
            hold(.pad(index), "SlipLoop/" + sizes[index], press: [.int(1)], release: [.int(0)])
        case .loop: sendDeck("SetCueLoop", .int(cue))
        case .slicer: break
        }
    }

    // MARK: LEDs

    func padLEDs() {
        let modes: [(String, PadMode)] = [("mode_hotcue", .hotCue), ("mode_roll", .roll), ("mode_loop", .loop), ("mode_slicer", .slicer)]
        for (name, mode) in modes { buttonLED(name, on: padMode == mode) }
        for (note, velocity) in zip(mapping.notes.pads, padColors()) { padLED(note, velocity) }
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
                // Held, it's vivid too (#151), so the sounding cue stands out in its hue, not whiter.
                return held.contains(.pad(index)) ? ringVelocity(Self.brightest(color)) : Self.velocity(color)
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

    /// A vivid velocity (#151) for an [r, g, b] color: the ring, and a held pad.
    static func vividVelocity(_ rgb: [Int]) -> UInt8 {
        guard rgb.count == 3 else { return off }
        return ControllerBridgeCore.vividVelocity(rgb[0], rgb[1], rgb[2])
    }

    /// The ring's and a held pad's velocity, by the Settings mapping (#151).
    func ringVelocity(_ rgb: [Int]) -> UInt8 {
        ringColors == .vivid ? Self.vividVelocity(rgb) : Self.velocity(rgb)
    }

    /// A pad or ring velocity for an [r, g, b] color.
    static func velocity(_ rgb: [Int]) -> UInt8 {
        // A user mapping can hold any list here until the mapping check (#24) refuses it.
        guard rgb.count == 3 else { return off }
        return rgbToVelocity(rgb[0], rgb[1], rgb[2])
    }
}

extension OSCArgument {
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
