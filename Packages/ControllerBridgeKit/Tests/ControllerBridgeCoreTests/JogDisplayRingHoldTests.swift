import Foundation
@testable import ControllerBridgeCore
import Testing

/// The ring holds while the jog display uploads (#422). On hardware, the LC6000's platter ring LED (Controller note 40)
/// lit through an LED repaint made the display drop uploads after one ack (1 stall in ~6-10 uploads); kept at 0 while
/// the uploads ran, 1 stall in ~480. The driver says when uploads run; the Coordinator holds the ring dark meanwhile.
@Suite("Jog display ring hold")
struct JogDisplayRingHoldTests {
    typealias Port = JogDisplayDriverTests.FakePort

    /// A beat-mode driver on its own, as the app runs it.
    static func driver(_ rig: Rig, _ port: Port) -> JogDisplayDriver {
        JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1,
                         renderBeat: { _, beat in [UInt8(beat), 0, 0, 255] }) { _ in [0, 0, 0, 255] }
    }

    /// Answers the driver's upload in flight: every ack, then the commit.
    static func answer(_ driver: JogDisplayDriver, _ port: Port) {
        let acks = port.wd.filter { $0.count > 6 && [0x0C, 0x0D, 0x0E].contains($0[6]) }.count
        port.wd.removeAll()
        for _ in 0..<acks { driver.reply(JogDisplayDriverTests.accepted) }
        driver.reply(JogDisplayDriverTests.committed)
    }

    @Test("Uploading from a new content until its fourth slot is stored, and not before or after")
    func uploadingSpansTheFour() throws {
        let rig = try Rig()
        let port = Port()
        let driver = Self.driver(rig, port)
        driver.connect()
        #expect(!driver.uploading)
        driver.show(JogDisplayContent(deck: 1, color: [255, 0, 0]))
        var during: [Bool] = []
        for _ in 0..<4 {
            during.append(driver.uploading)
            Self.answer(driver, port)
        }
        #expect(during == [true, true, true, true])
        #expect(!driver.uploading)
    }

    @Test("A unit that never answers: still uploading while slots are retried, not once every slot is given up on")
    func givenUp() throws {
        let rig = try Rig()
        let port = Port()
        let driver = Self.driver(rig, port)
        driver.connect()
        driver.show(JogDisplayContent(deck: 1, color: [255, 0, 0]))
        // Each of the 4 slots is tried 3 times, 5 s each: 60 s in all.
        for second in 1...59 {
            rig.clock.now = Double(second)
            driver.tick()
        }
        #expect(driver.uploading)
        rig.clock.now = 61
        driver.tick()
        #expect(!driver.uploading)
    }

    @Test("Disconnected mid-upload: not uploading")
    func disconnected() throws {
        let rig = try Rig()
        let port = Port()
        let driver = Self.driver(rig, port)
        driver.connect()
        driver.show(JogDisplayContent(deck: 1, color: [255, 0, 0]))
        #expect(driver.uploading)
        driver.disconnect()
        #expect(!driver.uploading)
    }
}
