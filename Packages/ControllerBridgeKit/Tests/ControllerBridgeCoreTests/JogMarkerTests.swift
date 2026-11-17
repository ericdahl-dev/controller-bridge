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

    // MARK: Touch wins (#306): a touched platter beats the deck's ramp, and easing back after

    @Test("While the platter is touched, BarRamp is ignored: the needle stays where the platter put it")
    func touchedIgnoresRamp() {
        var marker = JogMarker()
        marker.ramp(0, bpm: 120, at: 0)
        marker.platter(counts: 900, countsPerRev: 3600, at: 0, touched: true)   // a quarter turn
        marker.ramp(0.5, bpm: 120, at: 0.1, touched: true)
        marker.ramp(0.55, bpm: 120, at: 0.2, touched: true)
        #expect(marker.pitchBend(at: 0.3) == 4096)
    }

    @Test("Let go, the next ramp eases the needle back to the deck's phase over 250 ms, the short way round")
    func easesBack() {
        var marker = JogMarker()
        marker.ramp(0, bpm: 0, at: 0)
        marker.platter(counts: 900, countsPerRev: 3600, at: 0, touched: true)   // at 0.25
        marker.ramp(0.5, bpm: 0, at: 1, touched: false)                         // let go: the deck is at 0.5
        #expect(marker.pitchBend(at: 1) == 4096)         // starts where the platter left it
        #expect(marker.pitchBend(at: 1.125) == 6144)     // halfway: 0.375
        #expect(marker.pitchBend(at: 1.25) == 8192)      // there: 0.5
        marker.ramp(0.5, bpm: 0, at: 1.3, touched: false)
        #expect(marker.pitchBend(at: 1.3) == 8192)
        // The short way: from 0.95 to 0.05 goes forward through the top, not back round.
        var wrap = JogMarker()
        wrap.platter(counts: 3420, countsPerRev: 3600, at: 0, touched: true)   // 0.95
        wrap.ramp(0.05, bpm: 0, at: 1, touched: false)
        #expect(wrap.pitchBend(at: 1.125) == 0)
    }

    @Test("An untouched platter move (the edge) still gives way at the next ramp, at once, as before")
    func untouchedGivesWay() {
        var marker = JogMarker()
        marker.platter(counts: 900, countsPerRev: 3600, at: 0)
        marker.ramp(0.5, bpm: 0, at: 0.1)
        #expect(marker.pitchBend(at: 0.1) == 8192)
    }
}

/// The deck's own needle (#165, the user's pick): its phase in the bar from the deck's BarRamp, running on at the
/// deck's BPM between ramps (a bar of 4 beats is 240/bpm seconds), never more than a quarter turn past the last ramp.
@Suite("Jog marker from BarRamp")
struct JogMarkerRampTests {
    @Test("At the ramp, its phase: 0.5 is half a turn, 8192")
    func atRamp() {
        var marker = JogMarker()
        marker.ramp(0.5, bpm: 120, at: 10)
        #expect(marker.pitchBend(at: 10) == 8192)
    }

    @Test("Between ramps it runs on at the deck's BPM: 120 BPM is a 2 s bar, so 0.25 s later is 1/8 turn more (2048)")
    func runsOn() {
        var marker = JogMarker()
        marker.ramp(0.5, bpm: 120, at: 10)
        #expect(marker.pitchBend(at: 10.25) == 8192 + 2048)
    }

    @Test("No new ramp: it waits a quarter turn past the last one; a new ramp sets it again")
    func waits() {
        var marker = JogMarker()
        marker.ramp(0.875, bpm: 120, at: 10)
        #expect(marker.pitchBend(at: 20) == 2048)          // 0.875 + 0.25 = 1.125, wrapped to 1/8 turn
        marker.ramp(0.25, bpm: 120, at: 20)
        #expect(marker.pitchBend(at: 20) == 4096)
    }

    @Test("The platter moves it from where it is, as before")
    func platter() {
        var marker = JogMarker()
        marker.ramp(0.25, bpm: 120, at: 10)
        marker.platter(counts: 900, countsPerRev: 3600, at: 10)
        #expect(marker.pitchBend(at: 11) == 8192)
    }
}
