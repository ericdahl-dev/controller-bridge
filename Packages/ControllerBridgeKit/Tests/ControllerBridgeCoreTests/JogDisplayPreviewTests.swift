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

/// No controller connected (#221): the preview follows live Syndicate feedback for one deck, the user's pick (1-4),
/// else the first loaded deck.
@Suite("Jog display preview with no controller")
struct JogDisplayPreviewNoControllerTests {
    static let absent = MIDIEndpoint(id: 9999, name: "Not here")

    static func rig() throws -> (Rig, () -> [JogDisplayEvent]) {
        let rig = try Rig()
        let driver = JogDisplayDriver(port: nil, clock: rig.clock, log: rig.log, size: 1) { content in [UInt8(content.deck), 0, 0, 255] }
        var events: [JogDisplayEvent] = []
        driver.onEvent = { events.append($0) }
        rig.coordinator.attachJogDisplay(driver)
        rig.coordinator.start(controllers: (1...4).map { ControllerSettings(deck: $0, input: absent, output: nil, followLayers: false) })
        return (rig, { defer { events.removeAll() }; return events })
    }

    static func decks(_ events: [JogDisplayEvent]) -> [Int] {
        events.compactMap { if case .uploadStarted(_, let content, _) = $0 { return content.deck }; return nil }
    }

    @Test("With nothing connected, the first loaded deck shows: deck 3 once it has a track")
    func firstLoaded() throws {
        let (rig, take) = try Self.rig()
        _ = take()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)]))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 3))
        let events = take()
        #expect(Self.decks(events).last == 3)
        #expect(events.contains { if case .uploadStarted(_, let content, _) = $0 { return content.title == "Daybreak" }; return false })
    }

    @Test("The user's pick wins: deck 2, even with deck 3 loaded; nil goes back to the first loaded")
    func pick() throws {
        let (rig, take) = try Self.rig()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/3/Loaded", [.int(1)]))
        _ = take()
        rig.coordinator.setJogPreviewDeck(2)
        #expect(Self.decks(take()) == [2])
        rig.coordinator.setJogPreviewDeck(nil)
        #expect(Self.decks(take()) == [3])
    }
}

@Suite("Jog display preview from the pipe")
struct JogDisplayPreviewPipeTests {
    @Test("The preview deck the user picks reaches the Coordinator through the pipe")
    func pickFromThePipe() async throws {
        let (rig, take) = try JogDisplayPreviewNoControllerTests.rig()
        _ = take()
        let pipe = EventPipe()
        pipe.producer.setJogPreviewDeck(4)
        pipe.producer.finish()
        await Engine(coordinator: rig.coordinator, log: rig.log).run(pipe.events)
        #expect(JogDisplayPreviewNoControllerTests.decks(take()) == [4])
    }
}

/// Every deck in the simulator (#221 bug): the content of all four decks reaches it live, while only the followed
/// deck is uploaded.
@Suite("Jog display preview of every deck")
struct JogDisplayPreviewAllDecksTests {
    static func previews(_ events: [JogDisplayEvent]) -> [Int: String?] {
        var out: [Int: String?] = [:]
        for case .preview(let content) in events { out[content.deck] = content.title }
        return out
    }

    @Test("The driver reports a deck's preview on change only, and sends nothing for it")
    func driverPreview() {
        let (driver, take) = JogDisplayPreviewTests.previewing()
        let one = JogDisplayContent(deck: 1, color: [255, 0, 0], title: "A")
        driver.preview(one)
        driver.preview(one)
        driver.preview(JogDisplayContent(deck: 3, color: [0, 255, 255], title: "C"))
        #expect(take() == [.preview(one), .preview(JogDisplayContent(deck: 3, color: [0, 255, 255], title: "C"))])
    }

    @Test("No controller, live Syndicate: decks 1 and 3's tracks both reach the simulator; only the followed deck (3) uploads")
    func allDecks() throws {
        let (rig, take) = try JogDisplayPreviewNoControllerTests.rig()
        rig.coordinator.setJogPreviewDeck(3)
        _ = take()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 3, title: "Night Drive"))
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1, title: "Daybreak"))
        let events = take()
        let previews = Self.previews(events)
        #expect(previews[1] == "Daybreak")
        #expect(previews[3] == "Night Drive")
        #expect(JogDisplayPreviewNoControllerTests.decks(events) == [3], "only deck 3, the one followed, uploads")
    }
}
