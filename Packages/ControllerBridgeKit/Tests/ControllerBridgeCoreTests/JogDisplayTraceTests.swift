import Foundation
@testable import ControllerBridgeCore
import Testing

/// The Debug trace at the 50 a second live cadence (#605): the in-app preview's per-tick events filled a 20 MB file in
/// about a minute, so they stay out of it. What the unit gets is in the WD out lines; mode changes keep their lines.
@Suite("Jog display: the Debug trace")
struct JogDisplayTraceTests {
    @Test("The preview's per-tick events (drawnPreview, deckMarker) have no trace line; every other event has one")
    func previewEventsUntraced() {
        #expect(JogDisplayEvent.drawnPreview(DrawnDisplayState()).traceLine == nil)
        #expect(JogDisplayEvent.deckMarker(deck: 1, pitchBend: 8192).traceLine == nil)
        #expect(JogDisplayEvent.drawnPreviewsEnded.traceLine == "event drawnPreviewsEnded")
        #expect(JogDisplayEvent.connected.traceLine == "event connected")
        #expect(JogDisplayEvent.playLight(true).traceLine == "event playLight(true)")
        #expect(JogDisplayEvent.masterBeat(3).traceLine == "event masterBeat(3)")
    }

    @Test("Stale on and off (the waiting look) each get one trace line, on change only")
    func staleLines() {
        final class Lines: @unchecked Sendable { var all: [String] = [] }
        let lines = Lines()
        let driver = JogDisplayDriver(port: JogDisplayDriverTests.FakePort(), clock: Rig.FakeClock(), log: Rig.FakeLog(),
                                      size: 1) { _ in [0, 0, 0, 255] }
        driver.trace = { _, text in lines.all.append(text) }
        driver.setStale(true)
        driver.setStale(true)
        driver.setStale(false)
        driver.setStale(false)
        #expect(lines.all.filter { $0.contains("stale") } == ["jog display: Syndicate's feedback stale: the waiting look",
                                                             "jog display: Syndicate's feedback fresh: stale ends"])
    }
}
