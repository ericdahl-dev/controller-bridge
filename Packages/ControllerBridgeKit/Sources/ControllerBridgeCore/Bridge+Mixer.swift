// The mixer section (#207): channel faders, trim, EQ and filter knobs, cue/mute/solo, and VU meters, on mixer channel
// N for the controller driving deck N. Addresses are in MixerOSC (provisional for input until the #207 spike).

/// The mixer's state in a bridge.
struct MixerState {
    /// A 14-bit control's MSB, kept until its LSB arrives.
    var msb: [MixerValue: UInt8] = [:]
    /// The last value sent per control, rounded as sent.
    var lastSent: [MixerValue: Double] = [:]
    /// Recent sends, for telling Syndicate's echo from an outside change.
    var recentSends: [MixerValue: [(time: Double, value: Double)]] = [:]
    /// What Syndicate last reported per control.
    var reported: [MixerValue: Double] = [:]
    /// Controls waiting to meet Syndicate's value (pickup), and where each last was.
    var armed: Set<MixerValue> = []
    var position: [MixerValue: Double] = [:]
    /// The meter: Syndicate's latest level, the peak being held and since when, and what the LEDs show.
    var meterLevel: Double?
    var meterPeak = 0.0
    var meterPeakAt = -Double.infinity
    var meterSentAt: Double?
    var meterShown: UInt8?
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
        guard mixerPickedUp(kind, at: rounded), rounded != mixerState.lastSent[kind] else { return }
        mixerState.lastSent[kind] = rounded
        mixerState.recentSends[kind, default: []].removeAll { clock.now - $0.time > Self.echoWindow }
        mixerState.recentSends[kind, default: []].append((clock.now, rounded))
        send(address: MixerOSC.address(kind, channel: mapping.deck.number, root: root), [.float(Float(rounded))])
    }
}

extension Bridge {
    /// Syndicate's report of a mixer value on this deck's channel.
    func mixerFeedback(_ kind: MixerValue, _ arguments: [OSCArgument]) {
        guard let value = arguments.first?.number else { return }
        if mixerControls.contains(where: { $0.value == kind }) { mixerReported(kind, value) }
        if kind == .meter, let meter = mapping.mixer?.meter {
            mixerState.meterLevel = value
            if value >= mixerState.meterPeak || clock.now - mixerState.meterPeakAt > Double(meter.holdMs) / 1000 {
                mixerState.meterPeak = value
                mixerState.meterPeakAt = clock.now
            }
        }
        if mixerButtons.contains(where: { $0.value == kind }) {
            mixerState.reported[kind] = value
            mixerLEDs()
        }
    }

    /// The cue, mute and solo buttons, with the value each toggles.
    var mixerButtons: [(value: MixerValue, note: Int)] {
        guard let mixer = mapping.mixer else { return [] }
        let all: [(MixerValue, Int?)] = [(.cue, mixer.cueNote), (.mute, mixer.muteNote), (.solo, mixer.soloNote)]
        return all.compactMap { value, note in note.map { (value, $0) } }
    }

    /// A press of cue, mute or solo sends the opposite of what Syndicate last reported (PROVISIONAL: the input's
    /// meaning is unconfirmed until the #207 spike; sending the new state works whether Syndicate sets or toggles).
    /// Its LED waits for Syndicate's answer. False for any other note.
    func mixerNote(_ note: Int, pressed: Bool) -> Bool {
        guard let button = mixerButtons.first(where: { $0.note == note }) else { return false }
        guard pressed else { return true }
        let on = (mixerState.reported[button.value] ?? 0) > 0.5
        send(address: MixerOSC.address(button.value, channel: mapping.deck.number, root: root), [.int(on ? 0 : 1)])
        return true
    }

    /// The cue, mute and solo LEDs, from what Syndicate reported: full when on, else as an unlit button.
    func mixerLEDs() {
        for button in mixerButtons {
            let on = (mixerState.reported[button.value] ?? 0) > 0.5
            led(button.note, on ? fullLevel : (mapping.leds.dimUnlitButtons ? dimLevel : offLevel))
        }
    }

    /// A value the controller didn't send (another controller, the mouse) moved Syndicate away from the control, so
    /// pickup arms, as the pitch fader's (#22). Syndicate's echo of a send doesn't.
    private func mixerReported(_ kind: MixerValue, _ value: Double) {
        mixerState.reported[kind] = value
        guard let mixer = mapping.mixer, mixer.pickup else { return }
        let tolerance = mixer.pickupTolerance
        let echo = mixerState.lastSent[kind].map { abs($0 - value) <= tolerance } == true
            || (mixerState.recentSends[kind] ?? []).contains { clock.now - $0.time <= Self.echoWindow && abs($0.value - value) <= tolerance }
        if !echo {
            mixerState.armed.insert(kind)
            mixerState.position[kind] = nil
            mixerState.lastSent[kind] = nil
        }
    }

    /// Whether the control at `level` drives Syndicate: always unless armed; armed, once it's within tolerance of the
    /// reported value or moves across it.
    fileprivate func mixerPickedUp(_ kind: MixerValue, at level: Double) -> Bool {
        guard let mixer = mapping.mixer, mixer.pickup, mixerState.armed.contains(kind),
            let reported = mixerState.reported[kind]
        else { return true }
        let previous = mixerState.position[kind]
        mixerState.position[kind] = level
        let near = abs(level - reported) <= mixer.pickupTolerance
        let crossed = previous.map { ($0 - reported) * (level - reported) < 0 } ?? false
        guard near || crossed else { return false }
        mixerState.armed.remove(kind)
        return true
    }
}

extension Bridge {
    /// Puts the meter on its LEDs, at most `rate_hz` times a second: the peak while it holds, else the level now.
    /// Syndicate sends Meter around 200 times a second, far more than the LEDs need or the port should carry.
    func meterTick() {
        guard let meter = mapping.mixer?.meter, let level = mixerState.meterLevel else { return }
        if let sent = mixerState.meterSentAt, clock.now - sent < 1 / Double(max(1, meter.rateHz)) - 1e-9 { return }
        if clock.now - mixerState.meterPeakAt > Double(meter.holdMs) / 1000 {
            mixerState.meterPeak = level
            mixerState.meterPeakAt = clock.now
        }
        let value = meterValue(max(level, mixerState.meterPeak), meter)
        guard value != mixerState.meterShown else { return }
        guard ledCC(UInt8(meter.cc), value) else { return }
        mixerState.meterShown = value
        mixerState.meterSentAt = clock.now
    }

    /// The meter CC value for a level: the step for the share of segments lit, or the clip value above 1.0.
    private func meterValue(_ level: Double, _ meter: Mapping.Mixer.Meter) -> UInt8 {
        guard let top = meter.steps.last else { return 0 }
        if level > 1 { return UInt8(clamping: meter.clip ?? top) }
        let index = min(meter.steps.count - 1, max(0, Int((level * Double(meter.steps.count - 1)).rounded(.down))))
        return UInt8(clamping: meter.steps[index])
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
