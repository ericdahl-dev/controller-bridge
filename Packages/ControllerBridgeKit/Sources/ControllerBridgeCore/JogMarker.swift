// The jog display's marker (#165, #215): one hand on the platter display, moved by pitch bend on the WD port.
// It shows Syndicate's master clock, one turn per bar of four beats, from Header/Clock and Header/BPM. While the
// platter moves it follows the platter instead, and the next beat takes it back.

public struct JogMarker: Equatable, Sendable {
    private enum Mode: Equatable, Sendable {
        /// The clock hand: `base` turns at `since`, running a quarter turn per beat at `bpm`, but never past the beat.
        case clock(base: Double, since: Double, bpm: Double)
        /// Where the platter left it.
        case held(Double)
    }

    private var mode = Mode.held(0)

    public init() {}

    /// Syndicate's master clock reached `beat` (1-4) of the bar at `bpm`.
    public mutating func beat(_ beat: Int, bpm: Double, at time: Double) {
        mode = .clock(base: Double(max(1, min(4, beat)) - 1) / 4, since: time, bpm: bpm)
    }

    /// The platter moved by `counts` of `countsPerRev`: the hand moves with it, from where it is.
    public mutating func platter(counts: Int, countsPerRev: Int, at time: Double) {
        guard countsPerRev > 0 else { return }
        mode = .held(angle(at: time) + Double(counts) / Double(countsPerRev))
    }

    /// The hand's angle in turns at `time`, not yet wrapped.
    func angle(at time: Double) -> Double {
        switch mode {
        case .held(let angle): angle
        case .clock(let base, let since, let bpm): base + min(max(0, time - since) * bpm / 240, 0.25)
        }
    }

    /// The pitch bend that draws it: ⌊angle × 16384⌋, wrapped to 0...16383.
    public func pitchBend(at time: Double) -> Int {
        let turns = angle(at: time)
        let wrapped = turns - turns.rounded(.down)
        return Int((wrapped * 16384).rounded(.down)) & 0x3FFF
    }
}
