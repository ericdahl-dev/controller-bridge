// Track time on the drawn jog display (#460): when the last minute's warning shows red. The renderer draws it; the
// display firmware's C keeps the same rule.

public enum JogTrackTime {
    /// The warning covers this many seconds before the end.
    public static let warningSeconds = 60

    /// Red now? Playing, a known length, `warningSeconds` or less left, and in the first half of the second (`phase`,
    /// 0 to 1): a 1 Hz blink between red and the normal colours.
    public static func warning(elapsed: Int, length: Int, playing: Bool, phase: Double) -> Bool {
        playing && length > 0 && length - elapsed <= warningSeconds && phase < 0.5
    }
}
