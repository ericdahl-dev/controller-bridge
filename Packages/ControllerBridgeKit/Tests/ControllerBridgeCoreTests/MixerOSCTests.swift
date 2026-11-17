import ControllerBridgeCore
import Testing

/// Syndicate's mixer addresses (#207), feedback and (provisionally) input, from the real Resend capture on #207.
@Suite("Mixer OSC addresses")
struct MixerOSCTests {
    @Test("Each mixer value's address on channel 2")
    func addresses() {
        #expect(MixerValue.allCases.map { MixerOSC.address($0, channel: 2, root: "/Syndicate/") } == [
            "/Syndicate/Mixer/CH2/Volume", "/Syndicate/Mixer/CH2/Trim",
            "/Syndicate/Mixer/CH2/EQ/Low", "/Syndicate/Mixer/CH2/EQ/Mid", "/Syndicate/Mixer/CH2/EQ/High",
            "/Syndicate/Mixer/filter2.cut", "/Syndicate/Mixer/filter2.res", "/Syndicate/Mixer/filter2.width",
            "/Syndicate/Mixer/CH2/Cue", "/Syndicate/Mixer/CH2/Mute", "/Syndicate/Mixer/CH2/Solo",
            "/Syndicate/Mixer/CH2/Meter",
        ])
    }

    @Test("Feedback addresses read back to their channel and value; anything else isn't a mixer value")
    func parse() {
        #expect(MixerOSC.parse("/Syndicate/Mixer/CH3/EQ/Low", root: "/Syndicate/") == MixerOSC.Parsed(channel: 3, value: .eqLow))
        #expect(MixerOSC.parse("/Syndicate/Mixer/filter4.res", root: "/Syndicate/") == MixerOSC.Parsed(channel: 4, value: .filterRes))
        #expect(MixerOSC.parse("/Syndicate/Mixer/CH1/Meter", root: "/Syndicate/") == MixerOSC.Parsed(channel: 1, value: .meter))
        #expect(MixerOSC.parse("/Syndicate/Mixer/filter1.cutEnabled", root: "/Syndicate/") == nil)
        #expect(MixerOSC.parse("/Syndicate/Deck/1/Playing", root: "/Syndicate/") == nil)
        #expect(MixerOSC.parse("/Syndicate/Mixer/CHx/Volume", root: "/Syndicate/") == nil)
    }
}
