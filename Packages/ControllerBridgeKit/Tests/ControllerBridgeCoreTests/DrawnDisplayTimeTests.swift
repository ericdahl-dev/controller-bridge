@testable import ControllerBridgeCore
import Testing

/// The drawn display's time message (#460), as agent3 and agent1 agreed: op 06 `eh el lh ll`, len 5, elapsed and the
/// track's length in whole seconds, 14-bit hi/lo, clamped to 16383; length 0 is unknown (elapsed only, no arc).
@Suite("Drawn display: time")
struct DrawnDisplayTimeTests {
    static func time(_ elapsed: Int, _ length: Int) -> [UInt8] {
        [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x20, 0x00, 0x05, 0x06,
         UInt8(elapsed >> 7), UInt8(elapsed & 0x7F), UInt8(length >> 7), UInt8(length & 0x7F), 0xF7]
    }

    @Test("Elapsed and length in whole seconds, down to the second shown: 83.9 s of 428.5 s is 83 of 428")
    func seconds() {
        #expect(DrawnDisplay.Message.time(elapsed: 83.9, length: 428.5).bytes == Self.time(83, 428))
        #expect(DrawnDisplay.Message.time(elapsed: 0, length: 200).bytes == Self.time(0, 200))
    }

    @Test("Unknown, NaN or no length is 0; unknown or negative elapsed is 0")
    func unknown() {
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: nil).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: .nan).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: 12, length: 0).bytes == Self.time(12, 0))
        #expect(DrawnDisplay.Message.time(elapsed: nil, length: 200).bytes == Self.time(0, 200))
        #expect(DrawnDisplay.Message.time(elapsed: -3, length: 200).bytes == Self.time(0, 200))
    }

    @Test("Both clamp to 16383 (4:33:03)")
    func clamp() {
        #expect(DrawnDisplay.Message.time(elapsed: 20000, length: .infinity).bytes == Self.time(16383, 16383))
    }

    @Test("Elapsed past the end (Syndicate's position can run a hair over) stays as sent; the chip shows 0 remaining")
    func pastTheEnd() {
        #expect(DrawnDisplay.Message.time(elapsed: 201.2, length: 200).bytes == Self.time(201, 200))
    }
}

/// The time message at the Coordinator (#460): the front deck's position and length, sent when the shown second
/// changes, at most 4 a second, in the full state and heartbeat; image mode sends none.
@Suite("Drawn display: time from the deck")
struct DrawnDisplayTimeFlowTests {
    typealias Handshake = DrawnDisplayHandshakeTests

    static func times(_ port: Handshake.Port) -> [[UInt8]] { Handshake.drawn(port).filter { $0[9] == 0x06 } }
    static func position(_ seconds: Float) -> OSCMessage { OSCMessage("/Syndicate/Deck/1/Position", [.float(seconds)]) }

    /// Drawing deck 1 with Daybreak (428.5 s) loaded; WD cleared.
    static func drawing() throws -> (ProfileMatchingTests.ProfileRig, Handshake.Port) {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.jogDisplayReply(Handshake.answer)
        rig.coordinator.tick()
        port.wd.removeAll()
        return (rig, port)
    }

    @Test("A new shown second goes once; the same second again sends nothing")
    func perSecond() throws {
        let (rig, port) = try Self.drawing()
        rig.clock.now = 1
        rig.coordinator.feedback(Self.position(83.9))
        rig.coordinator.tick()
        #expect(Self.times(port) == [DrawnDisplay.Message.time(elapsedSeconds: 83, lengthSeconds: 428).bytes])
        port.wd.removeAll()
        rig.clock.now = 1.5
        rig.coordinator.feedback(Self.position(84.2))
        rig.coordinator.tick()
        rig.clock.now = 1.9
        rig.coordinator.feedback(Self.position(84.6))
        rig.coordinator.tick()
        #expect(Self.times(port) == [DrawnDisplay.Message.time(elapsedSeconds: 84, lengthSeconds: 428).bytes])
    }

    @Test("Scrubbing: at most 4 a second; the last place goes once the quarter second is up")
    func rateLimited() throws {
        let (rig, port) = try Self.drawing()
        for step in 0..<20 {
            rig.clock.now = 1 + Double(step) * 0.05
            rig.coordinator.feedback(Self.position(Float(10 + step * 10)))
            rig.coordinator.tick()
        }
        #expect(Self.times(port).count <= 5)
        port.wd.removeAll()
        rig.clock.now = 2.3
        rig.coordinator.tick()
        #expect(Self.times(port).last == DrawnDisplay.Message.time(elapsedSeconds: 200, lengthSeconds: 428).bytes)
    }

    @Test("A seek after steady play goes at once")
    func seekAtOnce() throws {
        let (rig, port) = try Self.drawing()
        rig.clock.now = 1
        rig.coordinator.feedback(Self.position(83.9))
        rig.coordinator.tick()
        port.wd.removeAll()
        rig.clock.now = 1.4
        rig.coordinator.feedback(Self.position(300.2))
        rig.coordinator.tick()
        #expect(Self.times(port) == [DrawnDisplay.Message.time(elapsedSeconds: 300, lengthSeconds: 428).bytes])
    }

    @Test("The full state after begin carries the time, after the needle and before the meter")
    func inFullState() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.feedback(Self.position(12.5))
        rig.coordinator.tick()
        port.wd.removeAll()
        rig.coordinator.jogDisplayReply(Handshake.answer)
        let ops = DrawnDisplayReconnectTests.ops(port)
        #expect(Array(ops.suffix(3)) == [0x08, 0x06, 0x0A])
        #expect(Self.times(port) == [DrawnDisplay.Message.time(elapsedSeconds: 12, lengthSeconds: 428).bytes])
    }

    @Test("Image mode sends no time")
    func notInImages() throws {
        let (rig, port, clock) = try Handshake.rig(.custom)
        clock.now = 0.5
        rig.coordinator.tick()
        port.wd.removeAll()
        rig.coordinator.feedback(JogDisplayContentTests.trackInfo(deck: 1))
        rig.coordinator.feedback(Self.position(83.9))
        rig.coordinator.tick()
        #expect(Self.times(port).isEmpty)
    }
}
