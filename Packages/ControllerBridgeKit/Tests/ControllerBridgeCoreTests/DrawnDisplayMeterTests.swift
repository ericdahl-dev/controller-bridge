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

    @Test("Drawing: the front deck's channel level goes out as op 0A (−36..+6 dB → 0-127, #582), at most 30 a second, only on change")
    func meterFromFeedback() throws {
        let (rig, port) = try Self.drawing()
        Self.level(rig, 0.5)
        Self.level(rig, channel: 2, 1.0)   // another deck's channel: not shown
        rig.clock.now = 0.01
        rig.coordinator.tick()
        // 0.5 is −6.0 dB: (−6.02 + 36) / 42 of 127, 91.
        #expect(Self.meters(port) == [DrawnDisplay.Message.meter(level: 91, peak: 91).bytes])
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

    /// #582: the ballistics (MeterBallistics). The level falls from full to empty in 0.5 s rather than dropping to the
    /// latest sample; the peak holds 0.3 s, then falls at the same rate instead of snapping to the level.
    /// On the dB scale (#582) 1.0 is 0 dB, 0.857 of full (109).
    @Test("The level falls smoothly and the peak holds 0.3 s, then falls: 1.0, then 0.25 after 0.05 s")
    func peakHold() throws {
        let (rig, port) = try Self.drawing()
        Self.level(rig, 1.0)
        rig.clock.now = 0.05
        rig.coordinator.tick()
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 109, peak: 109).bytes)
        Self.level(rig, 0.25)
        rig.clock.now = 0.1
        rig.coordinator.tick()
        // 0.857 less 0.05 s of fall (0.1): 0.757, 96; the peak still held at 109.
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 96, peak: 109).bytes)
        rig.clock.now = 0.4
        rig.coordinator.tick()
        // 0.35 s of fall: 0.157, 20. The peak held to 0.35, then 0.05 s of fall: 0.757, 96.
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 20, peak: 96).bytes)
    }

    @Test("A hit between two sends shows at the next send: 0.9 (−0.9 dB, 0.835) then 0.1 inside one 33 ms window, sent as 98, not 48")
    func hitBetweenSends() throws {
        let (rig, port) = try Self.drawing()
        Self.level(rig, 0.1)
        rig.clock.now = 1.0
        rig.coordinator.tick()
        port.wd.removeAll()
        rig.clock.now = 1.005
        Self.level(rig, 0.9)
        rig.clock.now = 1.006
        Self.level(rig, 0.1)
        for tick in [1.01, 1.02, 1.03, 1.04] {
            rig.clock.now = tick
            if tick > 1.01 { Self.level(rig, 0.1) }
            rig.coordinator.tick()
        }
        // Risen to 0.835 at 1.01, then 0.03 s of fall (0.06) by the send at 1.04: 0.775, 98; the peak 0.835, 106.
        #expect(Self.meters(port).first == DrawnDisplay.Message.meter(level: 98, peak: 106).bytes)
    }

    @Test("A steady level sends the meter once, then nothing new")
    func steadySendsNothing() throws {
        let (rig, port) = try Self.drawing()
        for step in 0..<100 {
            rig.clock.now = 1 + Double(step) * 0.01
            Self.level(rig, 0.5)
            rig.coordinator.tick()
        }
        #expect(Self.meters(port) == [DrawnDisplay.Message.meter(level: 91, peak: 91).bytes])
    }

    @Test("A deck switch moves the meter to the new deck's channel at once, in the same tick")
    func deckSwitch() throws {
        let (rig, port) = try Handshake.drawnLayers()
        Self.level(rig, channel: 1, 0.5)
        Self.level(rig, channel: 2, 0.25)
        rig.coordinator.tick()
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 91, peak: 91).bytes)
        let unit = JogDisplayRingHoldTests.lc6000.id
        rig.coordinator.midi(.noteOn(channel: 0, note: 51, velocity: 0), source: unit)
        rig.coordinator.midi(.noteOn(channel: 1, note: 51, velocity: 127), source: unit)
        rig.coordinator.tick()   // same instant: the rate limit doesn't hold the new deck back
        // 0.25 is −12.0 dB: 72.
        #expect(Self.meters(port).last == DrawnDisplay.Message.meter(level: 72, peak: 72).bytes)
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
