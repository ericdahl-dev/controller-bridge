import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn display's level meter (#461): the deck in front's mixer channel, from Syndicate's Mixer/CHn/Meter, with a
/// peak hold, through the Coordinator on a fake display port.
@Suite("Drawn display: the level meter")
struct DrawnDisplayMeterTests {
    typealias Handshake = DrawnDisplayHandshakeTests

    static func meters(_ port: Handshake.Port) -> [[UInt8]] { Handshake.drawn(port).filter { $0[9] == 0x0A } }
    static func meters(_ port: JogDisplayDriverTests.FakePort) -> [[UInt8]] { Handshake.drawn(port).filter { $0[9] == 0x0A } }
    static func level(_ rig: ProfileMatchingTests.ProfileRig, channel: Int = 1, _ value: Float) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Mixer/CH\(channel)/Meter", [.float(value)]))
    }

    static func drawing() throws -> (ProfileMatchingTests.ProfileRig, Handshake.Port) {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        rig.coordinator.tick()
        port.wd.removeAll()
        return (rig, port)
    }

    @Test("Drawing: the front deck's channel level goes out as op 0A (0..1 → 0-127), at most 30 a second, only on change")
    func meterFromFeedback() throws {
        let (rig, port) = try Self.drawing()
        Self.level(rig, 0.5)
        Self.level(rig, channel: 2, 1.0)   // another deck's channel: not shown
        rig.clock.now = 0.01
        rig.coordinator.tick()
        #expect(Self.meters(port) == [DrawnDisplay.Message.meter(level: 64, peak: 64).bytes])
        port.wd.removeAll()
        for step in 2...100 {
            rig.clock.now = Double(step) * 0.01
            Self.level(rig, Float(step % 2 == 0 ? 0.25 : 0.75))
            rig.coordinator.tick()
        }
        #expect(Self.meters(port).count <= 31 && Self.meters(port).count >= 20)
        port.wd.removeAll()
        rig.clock.now = 2
        rig.coordinator.tick()
        rig.clock.now = 2.5
        rig.coordinator.tick()
        let settled = Self.meters(port).count
        rig.clock.now = 3
        rig.coordinator.tick()
        #expect(Self.meters(port).count == settled)   // nothing new: nothing sent
    }

    /// #582: a send schedule 1/30 s apart, as the needle's (#561): a send that lands late on a 10 ms tick doesn't push
    /// the next one back. It was 25 a second.
    @Test("A second of 10 ms ticks with the level changing every tick sends the meter 30 times")
    func fullRate() throws {
        let (rig, port) = try Self.drawing()
        for step in 0..<100 {
            rig.clock.now = 1 + Double(step) * 0.01
            Self.level(rig, Float(step % 2 == 0 ? 0.2 : 0.9))
            rig.coordinator.tick()
        }
        #expect(Self.meters(port).count == 30)
    }

    @Test("The peak holds 0.3 s above the level, then falls to it")
    func peakHold() throws {
        let (rig, port) = try Self.drawing()
        Self.level(rig, 1.0)
        rig.clock.now = 0.05
        rig.coordinator.tick()
        Self.level(rig, 0.25)
        rig.clock.now = 0.1
        rig.coordinator.tick()
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 32, peak: 127).bytes)
        rig.clock.now = 0.4
        rig.coordinator.tick()
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 32, peak: 32).bytes)
    }

    @Test("A deck switch moves the meter to the new deck's channel at once, in the same tick")
    func deckSwitch() throws {
        let (rig, port) = try Handshake.drawnLayers()
        Self.level(rig, channel: 1, 0.5)
        Self.level(rig, channel: 2, 0.25)
        rig.coordinator.tick()
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 64, peak: 64).bytes)
        let unit = JogDisplayRingHoldTests.lc6000.id
        rig.coordinator.midi(.noteOn(channel: 0, note: 51, velocity: 0), source: unit)
        rig.coordinator.midi(.noteOn(channel: 1, note: 51, velocity: 127), source: unit)
        rig.coordinator.tick()   // same instant: the rate limit doesn't hold the new deck back
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 32, peak: 32).bytes)
    }

    @Test("With no mixer feedback the meter is empty (0, 0) in the full state, not stale; a deck with none shows empty too")
    func noFeedbackIsEmpty() throws {
        let (rig, port, _) = try Handshake.rig(.custom)
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(Self.meters(port) == [DrawnDisplay.Message.meter(level: 0, peak: 0).bytes])
        #expect(!Handshake.drawn(port).contains { $0[9] == 0x07 && $0[10] & 0x20 != 0 })   // not stale

        let (layers, wd) = try Handshake.drawnLayers()
        Self.level(layers, channel: 1, 0.5)
        layers.coordinator.tick()
        let unit = JogDisplayRingHoldTests.lc6000.id
        layers.coordinator.midi(.noteOn(channel: 0, note: 51, velocity: 0), source: unit)
        layers.coordinator.midi(.noteOn(channel: 1, note: 51, velocity: 127), source: unit)
        layers.coordinator.tick()
        #expect(Self.meters(wd).last == DrawnDisplay.Message.meter(level: 0, peak: 0).bytes)
    }

    @Test("While drawing, the mixer meter joins the required subscriptions (so a missing one is reported); not before, not after")
    func meterSubscription() throws {
        let (rig, _, _) = try Handshake.rig(.custom)
        #expect(!rig.coordinator.status.requiredSubscriptions.contains(.mixerMeter))   // still asking
        rig.coordinator.jogDisplayReply(Handshake.answer)
        #expect(rig.coordinator.status.requiredSubscriptions.contains(.mixerMeter))
        rig.coordinator.setJogDisplay(enabled: false)
        #expect(!rig.coordinator.status.requiredSubscriptions.contains(.mixerMeter))
    }
}
