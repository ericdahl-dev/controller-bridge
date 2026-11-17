// The jog display's marker (#165, #215): one hand on the platter display, moved by pitch bend on the WD port.
// It shows the deck's own phase in the bar, one turn per bar of four beats, from the deck's BarRamp and BPM (the
// user's pick: the needle is the deck, the lit ring segment is the master). The master-clock mode stays for #215.
// While the platter moves it follows the platter instead, and the next ramp takes it back. A touched platter wins
// outright (#306): the deck's ramp is ignored until it's let go, then the needle eases back to the deck's phase.

public struct JogMarker: Equatable, Sendable {
    private enum Mode: Equatable, Sendable {
        /// The clock hand: `base` turns at `since`, running a quarter turn per beat at `bpm`, but never past the beat.
        case clock(base: Double, since: Double, bpm: Double)
        /// The deck's phase: `phase` turns at `since`, running on at `bpm`, never more than a quarter turn past it.
        case ramp(phase: Double, since: Double, bpm: Double)
        /// Where the platter left it.
        case held(Double)
        /// Back from the platter to the deck's phase: from `from` at `start`, to the ramp, over `easeSeconds`.
        case easing(from: Double, start: Double, phase: Double, since: Double, bpm: Double)
    }

    private var mode = Mode.held(0)
    /// The platter is touched, or was until the next ramp: that ramp eases back instead of jumping.
    private var followingPlatter = false

    /// How long the needle takes to go back to the deck's phase after the platter is let go (#306).
    public static let easeSeconds = 0.25

    public init() {}

    /// Syndicate's master clock reached `beat` (1-4) of the bar at `bpm`.
    public mutating func beat(_ beat: Int, bpm: Double, at time: Double) {
        mode = .clock(base: Double(max(1, min(4, beat)) - 1) / 4, since: time, bpm: bpm)
    }

    /// The deck's BarRamp said it's `phase` (0..1) of the way through its bar, at `bpm`.
    /// With the platter `touched` it's ignored (#306): the needle stays with the platter.
    public mutating func ramp(_ phase: Double, bpm: Double, at time: Double, touched: Bool = false) {
        if touched {
            if !followingPlatter { mode = .held(angle(at: time)) }
            followingPlatter = true
            return
        }
        if followingPlatter {
            followingPlatter = false
            mode = .easing(from: angle(at: time), start: time, phase: phase, since: time, bpm: bpm)
            return
        }
        if case .easing(let from, let start, _, _, _) = mode, time - start < Self.easeSeconds {
            mode = .easing(from: from, start: start, phase: phase, since: time, bpm: bpm)
            return
        }
        mode = .ramp(phase: phase, since: time, bpm: bpm)
    }

    /// The deck stopped: the hand stays where it is at `time`.
    public mutating func freeze(at time: Double) {
        mode = .held(angle(at: time))
    }

    /// The platter moved by `counts` of `countsPerRev`: the hand moves with it, from where it is.
    /// A `touched` platter wins over the ramp until it's let go (#306).
    public mutating func platter(counts: Int, countsPerRev: Int, at time: Double, touched: Bool = false) {
        guard countsPerRev > 0 else { return }
        mode = .held(angle(at: time) + Double(counts) / Double(countsPerRev))
        if touched { followingPlatter = true }
    }

    /// The hand's angle in turns at `time`, not yet wrapped.
    func angle(at time: Double) -> Double {
        switch mode {
        case .held(let angle): angle
        case .clock(let base, let since, let bpm), .ramp(let base, let since, let bpm):
            base + min(max(0, time - since) * bpm / 240, 0.25)
        case .easing(let from, let start, let phase, let since, let bpm):
            Self.eased(from: from, to: phase + min(max(0, time - since) * bpm / 240, 0.25),
                       progress: min(1, max(0, time - start) / Self.easeSeconds))
        }
    }

    /// From `from` toward `target` the short way round (a delta within half a turn), `progress` of the way.
    private static func eased(from: Double, to target: Double, progress: Double) -> Double {
        var delta = target - from
        delta -= delta.rounded()
        return from + delta * progress
    }

    /// The pitch bend that draws it: ⌊angle × 16384⌋, wrapped to 0...16383.
    public func pitchBend(at time: Double) -> Int {
        let turns = angle(at: time)
        let wrapped = turns - turns.rounded(.down)
        return Int((wrapped * 16384).rounded(.down)) & 0x3FFF
    }
}
