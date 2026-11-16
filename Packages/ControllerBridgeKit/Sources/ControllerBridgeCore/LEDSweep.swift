import Foundation

/// The LED sweep (#26), as the Python `led-sweep` command ran it: the pads and ring through all 64 color velocities,
/// then every other note at full, dim and off, so the color table and LED notes can be checked by eye on any unit
/// (confirmed on a real LC6000, 2026-11-15, #12).
struct LEDSweep {
    struct Step {
        /// Seconds after the sweep starts.
        var at: Double
        var sends: [(note: Int, velocity: UInt8)]
        var captions: [String]
    }

    /// The steps for a controller's mapping: its pads and ring come from the active profile.
    static func steps(for mapping: Mapping, delay: Double) -> [Step] {
        let colorNotes = mapping.notes.pads + [mapping.leds.ring]
        let colors = (0..<64).map { velocity in
            let rgb = "r\(velocity >> 4 & 3) g\(velocity >> 2 & 3) b\(velocity & 3)"
            let caption = "  velocity " + String(format: "%2d (0x%02X)", velocity, velocity) + " = rgb222 " + rgb
            return Step(
                at: Double(velocity) * delay,
                sends: colorNotes.map { ($0, UInt8(velocity)) },
                captions: (velocity == 0 ? ["Color sweep: velocity shown on every pad and the ring. Note what each looks like."] : [])
                    + [caption]
            )
        }
        // Then the pads and ring off, and every other note 0-127 at full, dim, then off, a third of the delay apart.
        let buttonNotes = (0...127).filter { !colorNotes.contains($0) }
        let buttonsStart = 64 * delay
        var buttons: [Step] = []
        for (index, note) in buttonNotes.enumerated() {
            for (level, velocity) in [UInt8(127), 1, 0].enumerated() {
                var step = Step(at: buttonsStart + Double(index) * delay + Double(level) * delay / 3, sends: [(note, velocity)], captions: [])
                if index == 0, level == 0 {
                    step.sends = colorNotes.map { ($0, 0) } + step.sends
                    step.captions = ["Button sweep: each note at full, then dim, then off."]
                }
                if level == 2 { step.captions = ["  note \(note)"] + (index == buttonNotes.count - 1 ? ["LED sweep done."] : []) }
                buttons.append(step)
            }
        }
        return colors + buttons
    }
}
