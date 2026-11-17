// Pads, pad modes and cue colors (#18), as in the Python bridge.

/// What the pads do.
enum PadMode: CaseIterable {
    case hotCue, roll, loop, slicer

    /// The next mode for a cycling button (#198): Hot Cue → Roll → Loop → Slicer → Hot Cue.
    var next: PadMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
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
            self.applyPads(self.padModule.modeButton(mode))
            self.refreshLEDs()
        }
    }

    /// The one cycling mode button (#198); with the LC6000's four buttons it does nothing.
    func padModeCycle(_ pressed: Bool) {
        guard pressed else { return }
        let sends = padModule.cycle()
        guard !sends.isEmpty else { return }
        applyPads(sends)
        refreshLEDs()
    }

    /// A pad note in. A note from another mode's list (#225) switches to that mode first, letting held pads go, as
    /// a mode button does.
    func padNote(_ note: Int, pressed: Bool) -> Bool {
        let index: Int
        if pressed {
            guard let press = padModule.press(note: note) else { return false }
            applyPads(press.sends)
            index = press.index
        } else {
            guard let pad = padModule.pad(for: note) else { return false }
            index = pad.index
        }
        handlePad(index, pressed: pressed)
        return true
    }

    /// The pad a note plays (#225).
    func pad(for note: Int) -> (index: Int, mode: PadMode?)? { padModule.pad(for: note) }

    /// The notes the pads send and light in `mode` (#225).
    func padNotes(for mode: PadMode) -> [Int] { padModule.notes(for: mode) }

    /// Does what the pad module asks.
    func applyPads(_ sends: [PadModule.Send]) {
        for send in sends {
            switch send {
            case .releasePads: releasePads()
            }
        }
    }

    /// Releases every held pad, and nothing else.
    func releasePads() {
        for index in mapping.notes.pads.indices { releaseHold(.pad(index)) }
    }

    /// Syndicate's hot cues per deck: its Cues feedback has eight slots. A pad past them has no cue (#311).
    static let syndicateCues = 8

    /// A pad press or release. `index` is 0-based, so hot cue `index + 1`.
    func handlePad(_ index: Int, pressed: Bool) {
        defer { refreshLEDs() }
        guard pressed else { return releaseHold(.pad(index)) }
        let cue = Int32(index + 1)
        switch padMode {
        case .hotCue:
            guard index < Self.syndicateCues else { return }
            // Shift on a stopped deck (#358): go to the cue without playing.
            if shift, !playing, !playPending { return goToCuePaused(index + 1) }
            hold(.pad(index), "HotCue", press: [.int(cue), .int(1)], release: [.int(cue), .int(0)])
        case .roll:
            // The profile's roll sizes (#196); a pad past the list does nothing.
            let sizes = mapping.pads.rollSizes
            guard sizes.indices.contains(index) else { return }
            hold(.pad(index), "SlipLoop/" + sizes[index], press: [.int(1)], release: [.int(0)])
        case .loop:
            guard index < Self.syndicateCues else { return }
            sendDeck("SetCueLoop", .int(cue))
        case .slicer: break
        }
    }

    /// Shift + hot cue pad on a stopped deck (#358, #363): the cue module decides; the Bridge sends.
    func goToCuePaused(_ cue: Int) {
        applyCues(cueMemory.shiftPad(cue, duration: duration, now: clock.now))
    }

    /// A new track, or none: its cue times and cue point are unknown again.
    func forgetCues() {
        end(.newTrack)
        applyCues(cueMemory.forgetTrack())
    }

    /// Sends what the cue module asks: OSC to this deck, and quantize holds through the Bridge's one QuantizeOverride.
    func applyCues(_ sends: [CueModule.Send]) {
        for send in sends {
            switch send {
            case .osc(let path, let argument): sendDeck(path, argument)
            case .hold(let reason): overrideQuantize(reason)
            case .release(let reason): restoreQuantize(reason)
            }
        }
    }

    // MARK: LEDs

    func padLEDs() {
        let modes: [(String, PadMode)] = [("mode_hotcue", .hotCue), ("mode_roll", .roll), ("mode_loop", .loop), ("mode_slicer", .slicer)]
        for (name, mode) in modes { buttonLED(name, on: padMode == mode) }
        cycleButtonLED()
        // With notes per mode (#225), the current mode's notes carry the colors and the other modes' go dark.
        for (note, velocity) in zip(padNotes(for: padMode), padColors()) { padLED(note, velocity) }
        let lit = Set(padNotes(for: padMode))
        for note in padModule.allModeNotes where !lit.contains(note) { padLED(note, Self.off) }
        ringLED()
    }

    /// The cycling button's own LED (#198): the profile's velocity for the current mode. With none, it's left alone.
    private func cycleButtonLED() {
        guard mapping.pads.modeSelect == .cycle, let levels = mapping.pads.modeCycleVelocities,
              let note = mapping.notes.buttons["mode_cycle"] else { return }
        let velocity = switch padMode {
        case .hotCue: levels.hotcue
        case .roll: levels.roll
        case .loop: levels.loop
        case .slicer: levels.slicer
        }
        led(note, UInt8(clamping: velocity))
    }

    /// Hot Cue: each cue in its color. Loop: each cue in the loop color. Roll: every pad with a roll size in the roll
    /// color, the rest off (#311).
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
                return held.contains(.pad(index)) ? ringVelocity(Self.brightest(color)) : velocity(color)
            }
        case .loop: return cues.map { $0 == 0 ? Self.off : velocity(leds.loopPadColor) }
        case .roll: return cues.indices.map { $0 < mapping.pads.rollSizes.count ? velocity(leds.rollPadColor) : Self.off }
        case .slicer: return Array(repeating: Self.off, count: cues.count)
        }
    }

    /// The color scaled up so its strongest channel is 255.
    static func brightest(_ rgb: [Int]) -> [Int] {
        guard let top = rgb.max(), top > 0 else { return rgb }
        return rgb.map { $0 * 255 / top }
    }

    /// The ring's and a held pad's velocity, by the Settings mapping (#151), through the profile's color table (#197).
    func ringVelocity(_ rgb: [Int]) -> UInt8 {
        ringColors == .vivid ? mapping.leds.colorTable.vivid(for: rgb) : velocity(rgb)
    }

    /// A pad or ring velocity for an [r, g, b] color, through the profile's color table (#197). Not three values
    /// (a user mapping the check didn't see): off.
    func velocity(_ rgb: [Int]) -> UInt8 {
        mapping.leds.colorTable.velocity(for: rgb)
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
