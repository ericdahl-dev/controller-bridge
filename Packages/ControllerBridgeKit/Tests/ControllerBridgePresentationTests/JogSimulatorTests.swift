import ControllerBridgePresentation
import Foundation
import Testing

/// The jog display simulator's words (#221), apart from the SwiftUI and the renderer.
@Suite("Jog display simulator")
struct JogSimulatorTests {
    @Test("VoiceOver hears each deck's display as one sentence: deck, title, key, BPM and beat")
    func spokenSummary() {
        #expect(JogDeckSummary(deck: 1, title: "Daybreak", key: "A#m", bpm: 128, beat: 2).spoken
            == "Deck 1, Daybreak, A#m, 128 BPM, beat 2")
        #expect(JogDeckSummary(deck: 3, title: "Night Drive", key: nil, bpm: 127.5, beat: nil).spoken
            == "Deck 3, Night Drive, 127.5 BPM")
        #expect(JogDeckSummary(deck: 2, title: nil, key: nil, bpm: nil, beat: nil).spoken == "Deck 2, no track loaded")
        #expect(JogDeckSummary(deck: 4, title: "", key: "C", bpm: 0, beat: 1).spoken == "Deck 4, no track loaded",
                "an empty title is an empty deck, as Syndicate sends it")
    }

    @Test("Each preview's readout: the slot, the size, when it was uploaded and the unit's answer; or why there's none")
    func readout() {
        let utc = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_763_294_671)  // 2025-11-16 12:04:31 UTC
        #expect(JogUploadStatus.uploaded(slot: 2, bytes: 14_812, at: noon, accepted: true).readout(timeZone: utc)
            == "Slot 2 · 14,812 bytes · 12:04:31 · Accepted")
        #expect(JogUploadStatus.uploaded(slot: 1, bytes: 980, at: noon, accepted: false).readout(timeZone: utc)
            == "Slot 1 · 980 bytes · 12:04:31 · Refused")
        #expect(JogUploadStatus.notUploaded.readout(timeZone: utc) == "Nothing uploaded yet")
        #expect(JogUploadStatus.notConnected.readout(timeZone: utc) == "No LC6000 connected: preview only")
    }

    @Test("The marker redraws at most 30 times a second, and a burst still ends on its latest value")
    func markerLimiter() {
        var limiter = RedrawLimiter<Int>(interval: 1.0 / 30)
        // The first value draws at once.
        #expect(limiter.offer(10, at: 0.000) == 10)
        // Within 1/30 s (0.0333…) nothing draws; the newest value waits.
        #expect(limiter.offer(11, at: 0.010) == nil)
        #expect(limiter.offer(12, at: 0.020) == nil)
        // The tick after the interval draws the waiting value, the newest one.
        #expect(limiter.tick(at: 0.030) == nil)
        #expect(limiter.tick(at: 0.034) == 12)
        // Nothing waiting: a tick draws nothing.
        #expect(limiter.tick(at: 0.100) == nil)
        // A value long after the last draw draws at once.
        #expect(limiter.offer(13, at: 0.200) == 13)
    }

    @Test("The marker's pitch bend is a fraction of a turn: 0 is 12 o'clock, 4096 a quarter turn clockwise (provisional, #165)")
    func markerAngle() {
        #expect(JogMarkerAngle.degrees(pitchBend: 0) == 0)
        #expect(JogMarkerAngle.degrees(pitchBend: 4096) == 90)
        #expect(JogMarkerAngle.degrees(pitchBend: 8192) == 180)
        #expect(JogMarkerAngle.degrees(pitchBend: 12288) == 270)
        #expect(JogMarkerAngle.degrees(pitchBend: 16383) == 359.978_027_343_75)
    }
}
