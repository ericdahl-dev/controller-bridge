// The mixer section (#207): channel faders, trim, EQ and filter knobs, cue/mute/solo, and VU meters, on mixer channel
// N for the controller driving deck N. Addresses are in MixerOSC (provisional for input until the #207 spike).

/// The mixer's state in a bridge.
struct MixerState {
    /// A 14-bit control's MSB, kept until its LSB arrives.
    var msb: [MixerValue: UInt8] = [:]
    /// The last value sent per control, rounded as sent.
    var lastSent: [MixerValue: Double] = [:]
}

extension Bridge {
    /// The mixer section's faders and knobs, with the value each drives.
    var mixerControls: [(value: MixerValue, control: Mapping.Control)] {
        guard let mixer = mapping.mixer else { return [] }
        let all: [(MixerValue, Mapping.Control?)] = [
            (.volume, mixer.volume), (.trim, mixer.trim), (.eqHigh, mixer.eqHigh), (.eqMid, mixer.eqMid),
            (.eqLow, mixer.eqLow), (.filterCut, mixer.filter), (.filterRes, mixer.filterRes), (.filterWidth, mixer.filterWidth),
        ]
        return all.compactMap { value, control in control.map { (value, $0) } }
    }

    /// A CC from one of the mixer's faders or knobs: sent as 0..1 once it's whole. False for any other CC.
    func mixerCC(_ controller: Int, value: UInt8) -> Bool {
        for (kind, control) in mixerControls {
            if control.msbCC == controller {
                if control.bits == 7 {
                    sendMixer(kind, mixerLevel(from7Bit: value))
                } else {
                    mixerState.msb[kind] = value
                }
                return true
            }
            if control.bits == 14, control.lsbCC == controller {
                sendMixer(kind, mixerLevel(from14Bit: join14Bit(msb: mixerState.msb[kind] ?? 0, lsb: value)))
                return true
            }
        }
        return false
    }

    private func sendMixer(_ kind: MixerValue, _ level: Double) {
        let rounded = (level * 100_000).rounded() / 100_000
        guard rounded != mixerState.lastSent[kind] else { return }
        mixerState.lastSent[kind] = rounded
        send(address: MixerOSC.address(kind, channel: mapping.deck.number, root: mapping.osc.root), [.float(Float(rounded))])
    }
}

/// A 7-bit mixer control's value as 0..1. Syndicate centers EQ and trim at 0.5, so 64 (a knob's detent) is exactly
/// 0.5: below it each step is 1/128, above it 1/126, so 0 and 127 reach the ends (the 7-bit pitch fader's rule, #195).
func mixerLevel(from7Bit value: UInt8) -> Double {
    let v = Double(value & 0x7F)
    return v < 64 ? v / 128 : 0.5 + (v - 64) / 126
}

/// A 14-bit mixer control's value as 0..1, with 8192 exactly 0.5 by the same rule.
func mixerLevel(from14Bit value: Int) -> Double {
    let v = Double(max(0, min(16383, value)))
    return v < 8192 ? v / 16384 : 0.5 + (v - 8192) / 16382
}
