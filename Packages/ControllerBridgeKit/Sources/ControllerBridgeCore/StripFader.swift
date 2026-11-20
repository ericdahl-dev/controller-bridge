/// Shift + Needle Drop moves the deck's channel fader in Syndicate (#609). Whether a touch moves the fader or seeks is
/// fixed at touch-down. Relative: the fader moves from its level at touch-down by how far the finger travels, the
/// strip's length being the fader's range, clamped at both ends. Plain values in, the level to send out: the Bridge
/// sends the OSC.
struct StripFader {
    /// The last level known for each mixer channel: Syndicate's report, or where a touch left the fader.
    private var levels: [Int: Double] = [:]
    private var touch: Touch?

    private struct Touch {
        let channel: Int
        /// The level and strip position the travel counts from; nil until the first position after touch-down.
        var start: (level: Double, position: Double)?
        /// The fader's level as this touch last left it: an unchanged level isn't sent again.
        var level: Double?
    }

    /// Whether a touch is moving the fader now.
    var touching: Bool { touch != nil }

    /// Syndicate's report of a channel's Volume.
    mutating func reported(channel: Int, _ level: Double) {
        levels[channel] = level
    }

    /// The strip was touched with Shift held: this touch moves `channel`'s fader until it lifts.
    mutating func touchDown(channel: Int) {
        touch = Touch(channel: channel)
    }

    /// The finger lifted: where it left the fader is the level the next touch starts from, until Syndicate says
    /// otherwise (its Volume box may be off).
    mutating func touchUp() {
        if let touch, let level = touch.level { levels[touch.channel] = level }
        touch = nil
    }

    /// The finger at `position` (0–1): the level to send, if any.
    mutating func position(_ position: Double) -> (channel: Int, level: Double)? {
        guard var touch else { return nil }
        defer { self.touch = touch }
        guard let start = touch.start else {
            if let level = levels[touch.channel] {
                touch.start = (level, position)
                touch.level = level
            }
            return nil
        }
        let moved = start.level + position - start.position
        let level = min(max(moved, 0), 1)
        // Past an end, the travel counts from that end: coming back moves the fader at once.
        if level != moved { touch.start = (level, position) }
        guard level != touch.level else { return nil }
        touch.level = level
        return (touch.channel, level)
    }
}
