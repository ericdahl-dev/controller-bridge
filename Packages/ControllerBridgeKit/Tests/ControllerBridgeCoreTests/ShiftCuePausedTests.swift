import Foundation
@testable import ControllerBridgeCore
import Testing

/// Shift + hot cue pad on a stopped deck goes to the cue, paused (#358): Cue<n>, then Playing 0 the moment Syndicate
/// reports Playing 1. Syndicate has no jump-without-play input, and a pause sent before the launch cancels the jump
/// (the live check on #358). The LC6000 rig: Shift is note 26, pad 1 is note 32, all on channel 1.
@Suite("Shift + hot cue pad on a stopped deck")
struct ShiftCuePausedTests {
    static func started(_ override: String? = nil) throws -> Rig {
        let rig = try PadChannelCoordinatorTests.started(override)
        feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
        return rig
    }

    static func feed(_ rig: Rig, _ name: String, _ value: Int32) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/" + name, [.int(value)]))
    }

    static func shift(_ rig: Rig, _ down: Bool) {
        rig.coordinator.midi(down ? .noteOn(channel: 0, note: 26, velocity: 127) : .noteOff(channel: 0, note: 26, velocity: 0),
                             source: Rig.lc6000.id)
    }

    /// Shift held, pad `note` pressed and released, Shift let go.
    static func shiftPad(_ rig: Rig, _ note: UInt8 = 32) {
        shift(rig, true)
        PadChannelCoordinatorTests.press(rig, note, channel: 1)
        shift(rig, false)
    }

    static let cue1 = OSCMessage("/Syndicate/Deck/1/Cue1", [.int(1)])
    static let pause = OSCMessage("/Syndicate/Deck/1/Playing", [.int(0)])

    @Test("Stopped: Shift + pad 1 sends Cue1, never HotCue; the Playing 1 that follows gets one Playing 0")
    func stopped() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        #expect(rig.osc.sent == [Self.cue1])
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [Self.pause])
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 0)
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [], "only the launch the pad started is paused")
    }

    @Test("Q on (PlayPending 1 before Playing 1): no pause; the user hears the cue, as a normal hot cue")
    func quantizeOnPlays() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        rig.osc.sent.removeAll()
        Self.feed(rig, "PlayPending", 1)
        Self.feed(rig, "Playing", 1)
        Self.feed(rig, "PlayPending", 0)
        #expect(rig.osc.sent == [])
    }

    /// A 200-second track.
    static func loadTrack(_ rig: Rig, title: String = "t") {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/TrackInfo", [.string(title), .string("a"), .string("8A"), .float(120),
                                                                            .float(200), .int(100), .int(400), .string("track")]))
    }

    /// The fraction a WaveformSeek asked for, if that's all that was sent.
    static func seek(_ rig: Rig) -> Float? {
        guard rig.osc.sent.count == 1, rig.osc.sent[0].address == "/Syndicate/Deck/1/WaveformSeek",
              case .float(let fraction)? = rig.osc.sent[0].arguments.first else { return nil }
        return fraction
    }

    @Test("Learn, then seek (Q off): the first press learns cue 2 from the first Position (30.02 s, less 0.06); the next seeks there silently")
    func learnThenSeek() throws {
        let rig = try Self.started()
        Self.loadTrack(rig)
        Self.shiftPad(rig, 33)                       // pad 2
        Self.feed(rig, "Playing", 1)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Position", [.float(30.02)]))
        Self.feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
        Self.shiftPad(rig, 33)
        // Cue time 29.96 s; WaveformSeek lands 0.10 s before what it's asked (the live check), so it asks 30.06 / 200.
        let fraction = try #require(Self.seek(rig), "only a WaveformSeek: \(rig.osc.sent)")
        #expect(abs(fraction - 0.1503) < 0.00001)
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [], "a seek arms no pause")
    }

    static let hotCue2 = [OSCMessage("/Syndicate/Deck/1/HotCue", [.int(2), .int(1)]),
                          OSCMessage("/Syndicate/Deck/1/HotCue", [.int(2), .int(0)])]

    @Test("Q on, cue known: Shift + pad is a normal hot cue (a seek would snap to the grid and the user wants it to play)")
    func quantizeOnKnownCue() throws {
        let rig = try Self.started()
        Self.loadTrack(rig)
        Self.shiftPad(rig, 33)
        Self.feed(rig, "PlayPending", 1)
        Self.feed(rig, "Playing", 1)
        Self.feed(rig, "PlayPending", 0)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Position", [.float(30.02)]))
        Self.feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
        Self.shiftPad(rig, 33)
        #expect(rig.osc.sent == Self.hotCue2)
    }

    @Test("The quantize flag follows every launch from stopped: after a plain Play launch with no PlayPending, Shift + pad seeks again")
    func quantizeFollowsLaunches() throws {
        let rig = try Self.started()
        Self.loadTrack(rig)
        // Learned with Q on.
        Self.shiftPad(rig, 33)
        Self.feed(rig, "PlayPending", 1)
        Self.feed(rig, "Playing", 1)
        Self.feed(rig, "PlayPending", 0)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Position", [.float(30.02)]))
        Self.feed(rig, "Playing", 0)
        // The user turns Q off in Syndicate and presses Play: it starts at once, no PlayPending.
        Self.feed(rig, "Playing", 1)
        Self.feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
        Self.shiftPad(rig, 33)
        #expect(Self.seek(rig) != nil, "Q off again: a silent seek, \(rig.osc.sent)")
    }

    /// Learns cue 2 at 29.96 s with quantize off, and leaves the deck stopped.
    static func learnCue2(_ rig: Rig) {
        shiftPad(rig, 33)
        feed(rig, "Playing", 1)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/1/Position", [.float(30.02)]))
        feed(rig, "Playing", 0)
        rig.osc.sent.removeAll()
    }

    @Test("A new track forgets the cue times and the quantize flag: its cue 2 is tapped and learned again")
    func newTrackForgets() throws {
        let rig = try Self.started()
        Self.loadTrack(rig)
        Self.learnCue2(rig)
        Self.loadTrack(rig, title: "another")
        Self.shiftPad(rig, 33)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/1/Cue2", [.int(1)])])
    }

    @Test("The same track's TrackInfo again (a Resend) keeps what was learned")
    func resendKeeps() throws {
        let rig = try Self.started()
        Self.loadTrack(rig)
        Self.learnCue2(rig)
        Self.loadTrack(rig)
        Self.shiftPad(rig, 33)
        #expect(Self.seek(rig) != nil)
    }

    @Test("A launch more than 4 s after the press isn't the pad's: no pause")
    func timeout() throws {
        let rig = try Self.started()
        rig.clock.now = 100
        Self.shiftPad(rig)
        rig.osc.sent.removeAll()
        rig.clock.now = 104.5
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [])
    }

    @Test("A second Shift + pad press before the launch drops the pause: two quick taps play from the cue")
    func secondPressCancels() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        rig.osc.sent.removeAll()
        Self.shiftPad(rig)
        #expect(rig.osc.sent == [], "the second press sends nothing")
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [])
    }

    @Test("Play pressed before the launch drops the pause")
    func playCancels() throws {
        let rig = try Self.started()
        Self.shiftPad(rig)
        rig.osc.sent.removeAll()
        PadChannelCoordinatorTests.press(rig, 1, channel: 1)        // Play
        #expect(rig.osc.sent.map(\.address) == ["/Syndicate/Deck/1/PlayPause"])
        rig.osc.sent.removeAll()
        Self.feed(rig, "Playing", 1)
        #expect(rig.osc.sent == [])
    }

    // MARK: Where it applies (pins: these pass by construction, and guard the scope)

    @Test("Playing deck: Shift + pad is a normal hot cue")
    func playingDeck() throws {
        let rig = try Self.started()
        Self.feed(rig, "Playing", 1)
        rig.osc.sent.removeAll()
        Self.shiftPad(rig, 33)
        #expect(rig.osc.sent == Self.hotCue2)
    }

    @Test("Roll mode: Shift + pad on a stopped deck still rolls")
    func rollUnchanged() throws {
        let rig = try Self.started()
        PadChannelCoordinatorTests.press(rig, 28, channel: 1)         // mode_roll
        rig.osc.sent.removeAll()
        Self.shiftPad(rig)
        #expect(rig.osc.sent.allSatisfy { $0.address.contains("/SlipLoop/") } && !rig.osc.sent.isEmpty, "\(rig.osc.sent)")
    }

    @Test("A pad on the Shift pad channel (#324) on a stopped deck goes to the cue too")
    func shiftedChannel() throws {
        let rig = try Self.started(#"{ "pads": { "channel": 8, "shifted_channel": 9 } }"#)
        PadChannelCoordinatorTests.press(rig, 32, channel: 9)
        #expect(rig.osc.sent == [Self.cue1])
    }

    @Test("Per layer: deck 2's Shift pad on 11, deck 2 stopped, taps deck 2's cue")
    func perLayer() throws {
        let layers = [Mapping.Layer(channel: 1, deck: 1, padChannel: 8, shiftedPadChannel: 9),
                      Mapping.Layer(channel: 2, deck: 2, padChannel: 10, shiftedPadChannel: 11)]
        let rig = try PadChannelInheritanceTests.layered(#"""
            { "midi": { "layers": [ { "channel": 1, "deck": 1, "pad_channel": 8, "shifted_pad_channel": 9 },
                                    { "channel": 2, "deck": 2, "pad_channel": 10, "shifted_pad_channel": 11 } ] } }
            """#, layers: layers)
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(0)]))
        rig.osc.sent.removeAll()
        PadChannelCoordinatorTests.press(rig, 32, channel: 11)
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/2/Cue1", [.int(1)])])
        rig.osc.sent.removeAll()
        rig.coordinator.feedback(OSCMessage("/Syndicate/Deck/2/Playing", [.int(1)]))
        #expect(rig.osc.sent == [OSCMessage("/Syndicate/Deck/2/Playing", [.int(0)])])
    }
}
