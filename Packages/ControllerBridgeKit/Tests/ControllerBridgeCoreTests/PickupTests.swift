import ControllerBridgeCore
import Testing

/// Pitch pickup: after a load or an outside change, the fader does nothing until it meets Syndicate's TempoSlider.
/// Fader values: CC 8 (MSB) with CC 40 (LSB) at 0. 0x00 is -1.0, 0x40 is 0.0 (dead zone), 0x60 is 0.50009,
/// 0x50 is 0.25008, 0x70 is 0.75011.
@Suite("Pitch pickup")
struct PickupTests {
    static func started(_ override: String? = nil) throws -> Rig {
        let rig = try Rig(override: override)
        rig.coordinator.start()
        rig.osc.sent.removeAll()
        return rig
    }

    static func fader(_ rig: Rig, _ msb: UInt8) {
        rig.coordinator.midi(.controlChange(channel: 0, controller: 8, value: msb), source: Rig.lc6000.id)
    }

    static func report(_ rig: Rig, _ path: String, _ argument: OSCArgument) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + path, [argument]))
    }

    static func tempo(_ value: Float) -> OSCMessage {
        OSCMessage("/Syndicate/Deck/1/TempoSlider", [.float(value)])
    }

    @Test("After a load, the fader sends nothing until it comes within tolerance of the reported tempo slider")
    func picksUpWithinTolerance() throws {
        let rig = try Self.started()
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.5))
        Self.fader(rig, 0x00)
        #expect(rig.osc.sent == [])
        Self.fader(rig, 0x60)
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [Self.tempo(0.50009), Self.tempo(0.75011)])
    }

    @Test("A fader move that jumps across the reported value picks up")
    func picksUpOnCrossing() throws {
        let rig = try Self.started()
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.5))
        Self.fader(rig, 0x50)
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [Self.tempo(0.75011)])
    }

    @Test("Crossing is judged after invert: with pitch.invert, the fader meets a reported -0.5 on the inverted side")
    func crossingAfterInvert() throws {
        let rig = try Self.started(#"{ "pitch": { "invert": true } }"#)
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(-0.5))
        Self.fader(rig, 0x50)
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [Self.tempo(-0.75011)])
    }

    /// Loads a track at a reported 0.5 and picks the fader up there (0x60, 0.50009).
    static func pickedUp(_ override: String? = nil) throws -> Rig {
        let rig = try started(override)
        report(rig, "Loaded", .int(1))
        report(rig, "TempoSlider", .float(0.5))
        fader(rig, 0x60)
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("A reported tempo that the bridge didn't send (sync, a mouse edit) re-arms pickup")
    func outsideChangeRearms() throws {
        let rig = try Self.pickedUp()
        rig.clock.now = 2
        Self.report(rig, "TempoSlider", .float(0.0))
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [])
    }

    @Test("A late echo of a value sent during a move doesn't re-arm: send 0.406, 0.422, 0.438, then 0.406 comes back")
    func lateEchoDoesNotRearm() throws {
        let rig = try Self.pickedUp()
        Self.fader(rig, 0x5A)
        rig.clock.now = 0.1
        Self.fader(rig, 0x5B)
        rig.clock.now = 0.2
        Self.fader(rig, 0x5C)
        rig.clock.now = 0.3
        Self.report(rig, "TempoSlider", .float(0.40634))
        Self.fader(rig, 0x5D)
        #expect(rig.osc.sent == [Self.tempo(0.40634), Self.tempo(0.42196), Self.tempo(0.43759), Self.tempo(0.45321)])
    }

    @Test("While Syndicate reports the slider disabled, the fader is ignored; enabling it again re-arms pickup")
    func sliderDisabledIgnoresAndRearms() throws {
        let rig = try Self.pickedUp()
        Self.report(rig, "TempoSliderEnabled", .int(0))
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [])

        Self.report(rig, "TempoSliderEnabled", .int(1))
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [])
        Self.fader(rig, 0x60)
        #expect(rig.osc.sent == [Self.tempo(0.50009)])
    }

    @Test("A resync (unplug and replug) re-arms pickup")
    func resyncRearms() throws {
        let rig = try Self.pickedUp()
        RecoveryTests.unplug(rig)
        RecoveryTests.replug(rig)
        rig.osc.sent.removeAll()
        Self.fader(rig, 0x70)
        #expect(rig.osc.sent == [])
    }

    @Test("The pitch center LED is dim while the fader isn't picked up, then follows the usual rule")
    func centerLEDDimUntilPickedUp() throws {
        let rig = try Self.started()
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.0))
        #expect(rig.leds[42] == 1)
        Self.fader(rig, 0x40)          // 0.0: picked up at the center
        #expect(rig.leds[42] == 127)
        Self.fader(rig, 0x60)
        #expect(rig.leds[42] == 0)
    }

    @Test("pitch.pickup false: the fader drives the tempo at once, as before")
    func pickupOff() throws {
        let rig = try Self.started(#"{ "pitch": { "pickup": false } }"#)
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.5))
        Self.fader(rig, 0x00)
        #expect(rig.osc.sent == [Self.tempo(-1.0)])
        #expect(rig.leds[42] == 0)
    }

    @Test("pitch.pickup_tolerance sets how close counts as met: with 0.1, 0.406 meets a reported 0.5")
    func pickupTolerance() throws {
        let rig = try Self.started(#"{ "pitch": { "pickup_tolerance": 0.1 } }"#)
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.5))
        Self.fader(rig, 0x5A)
        #expect(rig.osc.sent == [Self.tempo(0.40634)])
    }

    /// TempoSlider messages sent to a deck, ignoring the Resend and anything else.
    static func tempoSends(_ rig: Rig, deck: Int) -> [OSCMessage] {
        rig.osc.sent.filter { $0.address == "/Syndicate/Deck/\(deck)/TempoSlider" }
    }

    /// Picked up on deck 1 at 0.5, then switched to deck 2 at t = 10.
    static func switchedToDeck2() throws -> Rig {
        let rig = try Self.started()
        Self.report(rig, "Loaded", .int(1))
        Self.report(rig, "TempoSlider", .float(0.5))
        Self.fader(rig, 0x60)
        rig.clock.now = 10
        rig.coordinator.setDeck(2, controller: 0)
        rig.osc.sent.removeAll()
        return rig
    }

    @Test("After a deck switch, the fader waits for the new deck's tempo instead of jumping it, then picks up as usual (#62)")
    func deckSwitchWaitsForTempo() throws {
        let rig = try Self.switchedToDeck2()
        rig.clock.now = 10.5
        Self.fader(rig, 0x70)
        #expect(Self.tempoSends(rig, deck: 2) == [])

        rig.clock.now = 10.6
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/TempoSlider", [.float(0.25)]))
        Self.fader(rig, 0x60)
        #expect(Self.tempoSends(rig, deck: 2) == [])
        Self.fader(rig, 0x50)
        #expect(Self.tempoSends(rig, deck: 2) == [OSCMessage("/Syndicate/Deck/2/TempoSlider", [.float(0.25008)])])
    }

    @Test("After a deck switch with no tempo report within 2 s (feedback_answer_ms), the fader passes through again")
    func deckSwitchWaitEnds() throws {
        let rig = try Self.switchedToDeck2()
        rig.clock.now = 11.9
        Self.fader(rig, 0x70)
        #expect(Self.tempoSends(rig, deck: 2) == [])
        rig.clock.now = 12.1
        Self.fader(rig, 0x50)
        #expect(Self.tempoSends(rig, deck: 2) == [OSCMessage("/Syndicate/Deck/2/TempoSlider", [.float(0.25008)])])
    }

    @Test("At launch, with no feedback at all, the fader passes through at once, as before")
    func launchPassesThrough() throws {
        let rig = try Self.started()
        Self.fader(rig, 0x60)
        #expect(Self.tempoSends(rig, deck: 1) == [Self.tempo(0.50009)])
    }
}
