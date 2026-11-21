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

    static let port = "/dev/cu.wchusbserial210"

    static func panel(_ rig: Rig, printing lines: [String]) {
        rig.usb.plugged = [USBDevice(vendor: ch340k.vendor, product: ch340k.product, name: "USB Serial", serialPort: port)]
        rig.serial.lines[port] = lines
    }

    @Test("A panel that boots while the app listens: found, with the build from its boot line")
    func panelBuild() async {
        let rig = Rig()
        Self.panel(rig, printing: ["ESP-ROM:esp32s3-20210327", "deck panel: boot, build 1d0683f", "deck panel: waiting"])
        let screen = await rig.screen()
        #expect(screen.panel.status == "Deck panel found")
        #expect(screen.panel.detail == "Build 1d0683f")
    }

    @Test("A panel that didn't boot while the app listened, or gave no real build: unplug and replug to read it",
          arguments: [
              [],
              ["deck panel: waiting"],
              ["deck panel: boot, build unknown"],
              ["deck panel: boot, build 1d06"],
              ["deck panel: boot, build 1D0683Z"],
          ])
    func panelBuildNotRead(lines: [String]) async {
        let rig = Rig()
        Self.panel(rig, printing: lines)
        let screen = await rig.screen()
        #expect(screen.panel.status == "Deck panel found")
        #expect(screen.panel.detail == "Build not read: unplug the panel and plug it back in to read it")
    }

    @Test("A development build (uncommitted changes, tools/deck-panel/git_sha.py) shows as one, SHA as printed")
    func panelDevelopmentBuild() async {
        let rig = Rig()
        Self.panel(rig, printing: ["deck panel: boot, build 1d0683f-dirty"])
        let found = await rig.finder.find()
        #expect(found.panel == .onSerial(build: PanelBuild(sha: "1d0683f-dirty")))
        let screen = UpdaterScreen(found: found, lc6000WarningAccepted: true)
        #expect(screen.panel.detail == "Build 1d0683f-dirty (a development build)")
    }
}
