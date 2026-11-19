@testable import ControllerBridgeCore
import Testing

/// The phase message at the Coordinator (#462): the front deck's PhaseOffset, as DrawnPhase makes it, on change and at
/// most 30 a second; a known one in the full state and the heartbeat; image mode sends none.
@Suite("Drawn display: phase from the deck")
struct DrawnDisplayPhaseFlowTests {
    typealias Handshake = DrawnDisplayHandshakeTests

    static func phases(_ port: Handshake.Port) -> [[UInt8]] { Handshake.drawn(port).filter { $0[9] == 0x0B } }
    static func offset(_ beats: Float, deck: Int = 1) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/\(deck)/PhaseOffset", [.float(beats)])
    }
    static func playing(_ on: Bool, deck: Int = 1) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/\(deck)/Playing", [.int(on ? 1 : 0)])
    }

    /// The coordinator's clock and the driver's, moved together.
    struct Clocks {
        let rig: ProfileMatchingTests.ProfileRig, driver: Rig.FakeClock
        var now: Double {
            get { driver.now }
            nonmutating set { rig.clock.now = newValue; driver.now = newValue }
        }
    }

    /// Drawing deck 1, loaded and playing; WD cleared.
    static func drawing() throws -> (ProfileMatchingTests.ProfileRig, Handshake.Port, Clocks) {
        let (rig, port, clock) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        rig.coordinator.feedback(Self.playing(true))
        rig.coordinator.tick()
        port.wd.removeAll()
        return (rig, port, Clocks(rig: rig, driver: clock))
    }

    @Test("A playing deck's offset goes as op 0B; the same again sends nothing")
    func onChange() throws {
        let (rig, port, clock) = try Self.drawing()
        clock.now = 1
        rig.coordinator.feedback(Self.offset(-0.04))
        rig.coordinator.tick()
        #expect(Self.phases(port) == [DrawnDisplay.Message.phase(-655).bytes])
        port.wd.removeAll()
        clock.now = 1.1
        rig.coordinator.feedback(Self.offset(-0.04))
        rig.coordinator.tick()
        #expect(Self.phases(port).isEmpty)
    }

    @Test("Stopping the deck sends unknown: the chip draws the plain rule")
    func stopping() throws {
        let (rig, port, clock) = try Self.drawing()
        clock.now = 1
        rig.coordinator.feedback(Self.offset(0.01))
        rig.coordinator.tick()
        port.wd.removeAll()
        clock.now = 1.1
        rig.coordinator.feedback(Self.playing(false))
        rig.coordinator.tick()
        #expect(Self.phases(port) == [DrawnDisplay.Message.phase(-8192).bytes])
    }
}
