import Foundation
@testable import ControllerBridgeCore
import Testing

/// The jog display's marker (#165, #215): Syndicate's master clock as a clock hand, one turn per bar, unless the
/// platter is moving, when it follows the platter. Sent as pitch bend, ⌊angle × 16384⌋. Worked by hand: at 120 BPM a
/// beat is 0.5 s and a bar of 4 is 2 s.
@Suite("Jog marker")
struct JogMarkerTests {
    @Test("Beat 1 at 120 BPM: 0 at the beat, an eighth of a turn (2048) a quarter-second on, and it waits at the beat's end (4096)")
    func clockHand() {
        var marker = JogMarker()
        marker.beat(1, bpm: 120, at: 0)
        #expect(marker.pitchBend(at: 0) == 0)
        #expect(marker.pitchBend(at: 0.25) == 2048)
        #expect(marker.pitchBend(at: 0.5) == 4096)
        #expect(marker.pitchBend(at: 0.9) == 4096)   // the next beat hasn't come: it doesn't run ahead
    }

    @Test("Beat 2 starts the second quarter (4096); beat 4's end is the top again (0)")
    func laterBeats() {
        var marker = JogMarker()
        marker.beat(2, bpm: 120, at: 10)
        #expect(marker.pitchBend(at: 10) == 4096)
        #expect(marker.pitchBend(at: 10.25) == 6144)
        marker.beat(4, bpm: 120, at: 11)
        #expect(marker.pitchBend(at: 11.5) == 0)
    }

    @Test("The platter turns it: 900 of 3600 counts is a quarter turn either way, from where it was")
    func platter() {
        var marker = JogMarker()
        marker.beat(2, bpm: 120, at: 0)   // 0.25
        marker.platter(counts: 900, countsPerRev: 3600, at: 0)
        #expect(marker.pitchBend(at: 0) == 8192)
        marker.platter(counts: -1800, countsPerRev: 3600, at: 0)
        #expect(marker.pitchBend(at: 0) == 0)
        marker.platter(counts: -900, countsPerRev: 3600, at: 0)
        #expect(marker.pitchBend(at: 0) == 12288)
    }

    @Test("While the platter moves, the clock doesn't pull it back; the next beat takes over again")
    func platterThenClock() {
        var marker = JogMarker()
        marker.beat(1, bpm: 120, at: 0)
        marker.platter(counts: 900, countsPerRev: 3600, at: 0)   // from 0 to a quarter
        #expect(marker.pitchBend(at: 0.3) == 4096)
        marker.beat(2, bpm: 120, at: 0.5)
        #expect(marker.pitchBend(at: 0.5) == 4096)
    }
}
