import DeviceFinder
import FirmwareModel
import Testing
import UpdaterScreen

/// The app shell (#685): two sections, deck panel and LC6000, saying what is connected. Driven by fake ports.
@Suite("Updater: what is connected")
struct UpdaterScreenTests {
    @Test("With nothing plugged in, both sections say nothing is connected")
    func nothingConnected() async {
        let screen = await Rig().screen()
        #expect(screen.panel.status == "Nothing connected")
        #expect(screen.lc6000.status == "Nothing connected")
    }
}
