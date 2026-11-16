import Foundation
@testable import ControllerBridgeCore
import Testing

/// The jog display preview (#221): with no port, the driver still renders and reports what it would show, for the
/// Diagnostics simulator, and sends nothing.
@Suite("Jog display preview")
struct JogDisplayPreviewTests {
    static func previewing() -> (JogDisplayDriver, () -> [JogDisplayEvent]) {
        let driver = JogDisplayDriver(port: nil, clock: Rig.FakeClock(), log: Rig.FakeLog(), size: 1, render: JogDisplayDriverTests.render)
        var events: [JogDisplayEvent] = []
        driver.onEvent = { events.append($0) }
        return (driver, { defer { events.removeAll() }; return events })
    }

    @Test("With no port, each new content is 'uploaded' and shown at once, alternating slots; the same content again does nothing")
    func uploads() {
        let (driver, take) = Self.previewing()
        let red = JogDisplayContent(deck: 1, color: [255, 0, 0]), yellow = JogDisplayContent(deck: 2, color: [255, 255, 0])
        driver.show(red)
        let bytes = JogDisplayDriverTests.upload(deck: 1, slot: 1).body.reduce(0) { $0 + $1.count }
        #expect(take() == [.uploadStarted(slot: 1, content: red, bytes: bytes), .shown(slot: 1)])
        driver.show(red)
        #expect(take() == [])
        driver.show(yellow)
        #expect(take().last == .shown(slot: 2))
        #expect(!driver.isConnected, "no hello without a port")
    }

    @Test("With no port, the marker and play light are reported on change")
    func markerAndLight() {
        let (driver, take) = Self.previewing()
        driver.marker(4096)
        driver.marker(4096)
        driver.playLight(true)
        driver.playLight(true)
        #expect(take() == [.marker(pitchBend: 4096), .playLight(true)])
    }
}
