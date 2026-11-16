import Foundation
@testable import ControllerBridgeCore
import Testing

/// The jog display at the Coordinator seam (#165): the display shows the deck in front, in its deck color, on connect,
/// on a layer change and on a deck-color change, and says goodbye when the unit goes. Syndicate's factory deck colors
/// (#123): deck 1 red, deck 2 yellow.
@Suite("Jog display at the Coordinator")
struct JogDisplayCoordinatorTests {
    typealias Port = JogDisplayDriverTests.FakePort

    /// What each upload showed, read back from the fake renderer's calls.
    final class Shown: @unchecked Sendable { var contents: [JogDisplayContent] = [] }

    static func attach(_ rig: Rig) -> (Port, Shown) {
        let port = Port(), shown = Shown()
        rig.coordinator.attachJogDisplay(JogDisplayDriver(port: port, clock: rig.clock, log: rig.log, size: 1) { content in
            shown.contents.append(content)
            return [UInt8(content.deck), 0, 0, 255]
        })
        return (port, shown)
    }

    /// Answers the upload in flight: every ack, then the commit.
    static func answer(_ rig: Rig, _ port: Port) {
        let acks = port.wd.filter { $0.count > 6 && [0x0C, 0x0D, 0x0E].contains($0[6]) }.count
        for _ in 0..<acks { rig.coordinator.jogDisplayReply(JogDisplayDriverTests.accepted) }
        rig.coordinator.jogDisplayReply(JogDisplayDriverTests.committed)
        port.wd.removeAll()
    }

    @Test("Connect says hello and shows deck 1 in red")
    func connect() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        #expect(port.controller == JogDisplay.hello)
        #expect(shown.contents == [JogDisplayContent(deck: 1, color: [255, 0, 0])])
    }

    @Test("Switching to layer 2 shows deck 2 in yellow, once the first image is up")
    func layerChange() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        rig.coordinator.setControllers(ControllerSettings.expanded(
            [ControllerSettings(deck: 1, input: Rig.lc6000, output: Rig.lc6000Out)], layers: LayersTests.lc6000Layers
        ))
        LayersTests.switchLayer(rig, from: 1, to: 2)
        Self.answer(rig, port)
        #expect(shown.contents.last == JogDisplayContent(deck: 2, color: [255, 255, 0]))
    }

    @Test("Syndicate changing deck 1's color redraws it")
    func colorChange() throws {
        let rig = try Rig()
        let (port, shown) = Self.attach(rig)
        rig.coordinator.start()
        Self.answer(rig, port)
        // Cue palette slot 1, deck 1's color (#123), now blue.
        rig.coordinator.feedback(OSCMessage("/Syndicate/ColorPalette", [.int(1), .int(0), .int(0), .int(255)]))
        #expect(shown.contents.last == JogDisplayContent(deck: 1, color: [0, 0, 255]))
    }

    @Test("Stop says goodbye")
    func stop() throws {
        let rig = try Rig()
        let (port, _) = Self.attach(rig)
        rig.coordinator.start()
        port.controller.removeAll()
        rig.coordinator.stop()
        #expect(port.controller == [JogDisplay.goodbye])
    }

    @Test("Unplugging the unit says goodbye; plugging it back says hello again")
    func unplug() throws {
        let rig = try Rig()
        let (port, _) = Self.attach(rig)
        rig.coordinator.start()
        port.controller.removeAll()
        rig.midi.sources.removeAll { $0.id == Rig.lc6000.id }
        rig.coordinator.devicesChanged()
        #expect(port.controller == [JogDisplay.goodbye])
        rig.midi.sources.append(Rig.lc6000)
        rig.coordinator.devicesChanged()
        #expect(port.controller == [JogDisplay.goodbye] + JogDisplay.hello)
    }
}
