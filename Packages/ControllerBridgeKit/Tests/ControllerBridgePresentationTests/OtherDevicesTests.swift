import ControllerBridgePresentation
import Testing

/// MIDI sources no controller profile matches (#43). A Mac nearly always has some (IAC Bus, virtual ports), so they
/// sit in a quiet gray list, unless no controller is connected: then the first one is probably the user's controller.
@Suite("Other MIDI devices")
struct OtherDevicesTests {
    @Test("With a controller connected, unmatched devices are one quiet gray list, with no orange")
    func quietListWhileConnected() {
        let devices = OtherDevices(unmatched: ["IAC Bus 1", "DDJ-FLX4"], controllerConnected: true)
        #expect(devices.highlighted == nil)
        #expect(devices.summary == "OTHER MIDI DEVICES (2)")
        #expect(devices.rows == ["IAC Bus 1 · no profile", "DDJ-FLX4 · no profile"])
    }

    @Test("With no controller connected, the first unmatched device is the orange NO PROFILE row; the rest stay gray")
    func firstIsHighlightedWithoutAController() {
        let devices = OtherDevices(unmatched: ["DDJ-FLX4", "IAC Bus 1"], controllerConnected: false)
        #expect(devices.highlighted == StatusLight(label: "DDJ-FLX4", word: "NO PROFILE", tone: .attention))
        #expect(devices.summary == "OTHER MIDI DEVICES (1)")
        #expect(devices.rows == ["IAC Bus 1 · no profile"])
    }

    @Test("No unmatched devices: no row and no list")
    func nothingToShow() {
        #expect(OtherDevices(unmatched: [], controllerConnected: false) == OtherDevices(unmatched: [], controllerConnected: true))
        let devices = OtherDevices(unmatched: [], controllerConnected: false)
        #expect(devices.highlighted == nil && devices.summary == nil && devices.rows.isEmpty)
    }
}
