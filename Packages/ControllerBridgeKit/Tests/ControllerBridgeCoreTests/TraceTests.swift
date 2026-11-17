import Foundation
@testable import ControllerBridgeCore
import Testing

/// The debug trace (#395): what Debug builds write to os_log and to a rolling file, so an agent can read what the
/// controller, Syndicate and the jog display did without asking for a paste.
@Suite("Debug trace")
struct TraceTests {
    @Test("One line: UTC time to the millisecond, the category padded to 13, the text")
    func lineFormat() {
        let at = Date(timeIntervalSince1970: 1_763_332_863.123)   // 2025-11-16T22:41:03.123Z
        #expect(TraceLine.format(at: at, .oscIn, "/Syndicate/Deck/1/Playing 1")
            == "2025-11-16T22:41:03.123Z osc-in        /Syndicate/Deck/1/Playing 1")
        #expect(TraceLine.format(at: at, .subscriptions, "Cues: off")
            == "2025-11-16T22:41:03.123Z subscriptions Cues: off")
    }

    @Test("Each category's name, as os_log and the file use it")
    func categoryNames() {
        #expect(TraceCategory.allCases.map(\.rawValue) == [
            "midi-in", "midi-out", "osc-in", "osc-out", "jog-display", "coordinator", "capture", "quantize",
            "subscriptions", "error",
        ])
    }
}
