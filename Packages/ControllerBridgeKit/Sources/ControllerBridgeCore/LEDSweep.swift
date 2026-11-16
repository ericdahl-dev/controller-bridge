import Foundation

/// The LED sweep (#26), as the Python `led-sweep` command ran it: the pads and ring through all 64 color velocities,
/// so the PROVISIONAL color table can be checked by eye on real hardware.
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
        return (0..<64).map { velocity in
            let rgb = "r\(velocity >> 4 & 3) g\(velocity >> 2 & 3) b\(velocity & 3)"
            let caption = "  velocity " + String(format: "%2d (0x%02X)", velocity, velocity) + " = rgb222 " + rgb
            return Step(
                at: Double(velocity) * delay,
                sends: colorNotes.map { ($0, UInt8(velocity)) },
                captions: (velocity == 0 ? ["Color sweep: velocity shown on every pad and the ring. Note what each looks like."] : [])
                    + [caption]
            )
        }
    }
}
