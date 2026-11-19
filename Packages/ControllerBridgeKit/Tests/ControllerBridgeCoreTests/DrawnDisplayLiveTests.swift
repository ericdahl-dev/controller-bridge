import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn display's needle, master beat and play state (#459), through the Coordinator on a fake display port.
@Suite("Drawn display: needle, master beat and play state")
struct DrawnDisplayLiveTests {
    typealias Handshake = DrawnDisplayHandshakeTests

    /// Drawn mode, deck 1 loaded and playing at 120 BPM from BarRamp 0 at t = 0.
    static func playing() throws -> (ProfileMatchingTests.ProfileRig, Handshake.Port) {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        for (path, value) in [("Playing", OSCArgument.int(1)), ("BPM", .float(120)), ("BarRamp", .float(0))] {
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [value]))
        }
        port.wd.removeAll()
        return (rig, port)
    }

    static func ops(_ port: Handshake.Port, _ op: UInt8) -> [[UInt8]] { Handshake.drawn(port).filter { $0[9] == op } }

    @Test("Drawing: the needle goes out as op 09, at most 30 a second, and never as pitch bend")
    func needleAsMessage() throws {
        let (rig, port) = try Self.playing()
        for step in 1...100 {
            rig.clock.now = Double(step) * 0.01
            // Syndicate's BarRamp each beat (half a second at 120): a quarter of the bar each time.
            if step % 50 == 0 { rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/BarRamp", [.float(Float(step) / 200)])) }
            rig.coordinator.tick()
        }
        let needles = Self.ops(port, 0x09)
        #expect(needles.count >= 25 && needles.count <= 31)
        #expect(!port.wd.contains { $0.first == 0xE0 })
        // Nearly a second on at 120 BPM: close to half a bar, 8192 (the last send may be up to 1/30 s earlier).
        let last = needles.last.map { Int($0[10]) << 7 | Int($0[11]) } ?? 0
        #expect((7600...8192).contains(last))
    }

    @Test("Paused, the needle holds: no needle message while nothing changes")
    func pausedHolds() throws {
        let (rig, port) = try Self.playing()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)]))
        rig.clock.now = 0.5
        rig.coordinator.tick()
        port.wd.removeAll()
        for step in 1...50 {
            rig.clock.now = 0.5 + Double(step) * 0.02
            rig.coordinator.tick()
        }
        #expect(Self.ops(port, 0x09).isEmpty)
    }
}
