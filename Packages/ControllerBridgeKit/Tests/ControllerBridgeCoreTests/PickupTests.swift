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
}
