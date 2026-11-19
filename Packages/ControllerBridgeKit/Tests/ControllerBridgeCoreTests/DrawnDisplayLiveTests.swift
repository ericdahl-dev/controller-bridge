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

    static func clock(_ rig: ProfileMatchingTests.ProfileRig, _ beat: Int) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Header/Clock", [.int(Int32(beat))]))
    }

    @Test("Each master beat sends one beat message, a repeat sends none, and no image is shown while drawing")
    func beatPerBeat() throws {
        let (rig, port) = try Self.playing()
        for beat in [1, 2, 2, 3, 4, 1] { Self.clock(rig, beat) }
        #expect(Self.ops(port, 0x08).map { $0[10] } == [1, 2, 3, 4, 1])
        #expect(!port.wd.contains { $0.count > 6 && $0[0] == 0xF0 && $0[6] == 0x0A })
    }

    @Test("With no master clock: the full state's beat is 0 (no section lit), and the needle still moves")
    func noClock() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(Self.ops(port, 0x08).map { $0[10] } == [0])
        for (path, value) in [("Playing", OSCArgument.int(1)), ("BPM", .float(120)), ("BarRamp", .float(0))] {
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [value]))
        }
        rig.clock.now = 0.25
        rig.coordinator.tick()
        #expect(!Self.ops(port, 0x09).isEmpty)
    }

    @Test("The state carries loaded, playing and play pending for the deck in front; only changes go out")
    func stateFlags() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)   // deck 1 loaded
        rig.coordinator.tick()
        port.wd.removeAll()
        func step(_ path: String, _ value: Int32) {
            rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [.int(value)]))
            rig.coordinator.tick()
        }
        step("Playing", 1)
        step("Playing", 1)
        step("Playing", 0)
        step("PlayPending", 1)
        step("PlayPending", 0)
        step("Playing", 1)
        #expect(Self.ops(port, 0x07).map { $0[10] } == [0x03, 0x01, 0x05, 0x01, 0x03])
    }
}
