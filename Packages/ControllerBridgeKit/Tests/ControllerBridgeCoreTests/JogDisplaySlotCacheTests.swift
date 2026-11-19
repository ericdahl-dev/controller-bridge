import Foundation
@testable import ControllerBridgeCore
import Testing

/// Every deck's beat images stay on the unit (#424): deck N's beat B lives in slot (N - 1) × 4 + B, of the 15 slots the
/// unit can show, so a deck switch is one show message and no upload. Deck 4 has three slots: on beat 4 its screen holds.
@Suite("Jog display slot cache")
struct JogDisplaySlotCacheTests {
    typealias Port = JogDisplayDriverTests.FakePort

    static func content(_ deck: Int, title: String? = nil) -> JogDisplayContent {
        JogDisplayContent(deck: deck, color: [255, 0, 0], title: title)
    }

    /// The slot of each upload in `port`'s WD messages: 0E's first payload byte.
    static func uploadSlots(_ port: Port) -> [UInt8] {
        port.wd.filter { $0.count > 9 && $0[6] == 0x0E }.map { $0[9] }
    }

    /// Answers uploads until none is in flight; returns every slot uploaded, in order.
    static func settle(_ driver: JogDisplayDriver, _ port: Port) -> [UInt8] {
        var slots: [UInt8] = []
        while driver.uploading {
            slots += uploadSlots(port)
            JogDisplayRingHoldTests.answer(driver, port)
        }
        return slots
    }

    /// A connected beat-mode driver with deck 1 in front and decks 2 and 3 kept, all stored.
    static func cached() throws -> (JogDisplayDriver, Port) {
        let rig = try Rig()
        let port = Port()
        let driver = JogDisplayRingHoldTests.driver(rig, port)
        driver.connect()
        driver.show(content(1))
        driver.keep(content(2))
        driver.keep(content(3))
        #expect(settle(driver, port) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        port.wd.removeAll()
        return (driver, port)
    }

    @Test("Decks 1-3 go up into slots 1-12, the deck in front first; a switch to deck 2 is one show of its slot, no upload")
    func switchShowsCachedSlot() throws {
        let (driver, port) = try Self.cached()
        driver.show(Self.content(2))
        #expect(port.wd == [JogDisplay.show(slot: 5)])
        #expect(!driver.uploading)
    }
}
