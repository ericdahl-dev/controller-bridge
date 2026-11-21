import DeviceFinder
import Foundation
import Testing
import UpdaterScreen

/// The driver guide (#688): a panel whose chip has no driver gets the steps to install WCH's CH34x driver.
@Suite("Updater: the deck panel's driver guide")
struct DriverGuideTests {
    static func panelWithoutDriver(_ rig: Rig) {
        rig.usb.plugged = [USBDevice(vendor: 0x1A86, product: 0x7522, name: "USB Serial")]
    }

    @Test("A panel with no driver: the section carries the four steps in order, and WCH's download page")
    func guideSteps() async throws {
        let rig = Rig()
        Self.panelWithoutDriver(rig)
        let guide = try #require(await rig.screen().panel.guide)
        #expect(guide.steps == [
            "Download the CH34x driver for macOS from WCH, the chip's maker.",
            "Open the download, drag CH34xVCPDriver to Applications, open it, and click Install.",
            "If macOS asks, allow the driver in System Settings > General > Login Items & Extensions > Driver Extensions.",
            "Unplug the panel and plug it back in. This app looks again by itself.",
        ])
        #expect(guide.link == URL(string: "https://www.wch-ic.com/downloads/CH34XSER_MAC_ZIP.html"))
    }

    @Test("The guide links only to WCH's own site, over https")
    func guideLinksOnlyToWCH() async throws {
        let rig = Rig()
        Self.panelWithoutDriver(rig)
        let guide = try #require(await rig.screen().panel.guide)
        #expect(guide.link.scheme == "https")
        #expect(guide.link.host == "www.wch-ic.com")
        for step in guide.steps {
            #expect(!step.contains("http"), "a step carries a link: \(step)")
        }
    }
}
