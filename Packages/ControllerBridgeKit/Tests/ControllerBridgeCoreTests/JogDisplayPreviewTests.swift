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

/// The preview at the Coordinator seam (#221): with Settings' switch off, nothing reaches the unit, but the simulator
/// still sees the deck in front, its marker while playing, and the play light.
@Suite("Jog display preview at the Coordinator")
struct JogDisplayPreviewCoordinatorTests {
    @Test("Switch off: zero bytes to either port, and the simulator still gets deck 2's content, its marker and the light")
    func switchOffStillPreviews() throws {
        let rig = try Rig()
        let port = JogDisplayCoordinatorTests.Port()
        let driver = JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1) { content in [UInt8(content.deck), 0, 0, 255] }
        var events: [JogDisplayEvent] = []
        driver.onEvent = { events.append($0) }
        rig.coordinator.attachJogDisplay(driver)
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers
        ))
        LayersTests.switchLayer(rig, from: 1, to: 2)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 2))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(1)]))
        for step in 1...20 { rig.clock.now = Double(step) * 0.05; rig.coordinator.tick() }

        #expect(port.controller == [])
        #expect(port.wd == [])
        let shownDecks = events.compactMap { if case .uploadStarted(_, let content, _) = $0 { return content.deck }; return nil }
        #expect(shownDecks.last == 2)
        #expect(events.contains { if case .marker = $0 { return true }; return false })
        #expect(events.contains(.playLight(true)))
        #expect(!events.contains(.connected))
    }
}
