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

    /// The CrowPanel's USB serial chip, a CH340K (tools/deck-panel/README.md).
    static let ch340k = (vendor: UInt16(0x1A86), product: UInt16(0x7522))

    @Test("A panel on USB with no serial port: found, and its driver is missing")
    func panelWithoutDriver() async {
        let rig = Rig()
        rig.usb.plugged = [USBDevice(vendor: Self.ch340k.vendor, product: Self.ch340k.product, name: "USB Serial")]
        let screen = await rig.screen()
        #expect(screen.panel.status == "Deck panel found")
        #expect(screen.panel.detail == "The USB driver for its chip is missing")
        #expect(screen.lc6000.status == "Nothing connected")
    }
}
