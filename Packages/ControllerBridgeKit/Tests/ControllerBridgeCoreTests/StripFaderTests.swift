import Foundation
@testable import ControllerBridgeCore
import Testing

/// Shift + Needle Drop moves the deck's channel fader in Syndicate (#609). The LC6000 sends the same strip CCs (64/65)
/// and touch note (70) with Shift held as without; Shift is note 26.
@Suite("Shift + Needle Drop strip fader")
struct StripFaderTests {
    typealias C = ContinuousTests

    static func note(_ rig: Rig, _ note: UInt8, _ down: Bool) {
        rig.coordinator.midi(down ? .noteOn(channel: 0, note: note, velocity: 127) : .noteOff(channel: 0, note: note, velocity: 0),
                             source: Rig.lc6000.id)
    }

    static func shift(_ rig: Rig, _ down: Bool) { note(rig, 26, down) }
    static func touch(_ rig: Rig, _ down: Bool) { note(rig, 70, down) }

    /// The strip at `position` (0-16383), MSB then LSB, as the unit sends it.
    static func at(_ rig: Rig, _ position: Int) { C.strip(rig, UInt8(position >> 7), UInt8(position & 0x7F)) }

    static func volume(_ rig: Rig, channel: Int = 1, _ level: Float) {
        rig.coordinator.feedback(OSCMessage("/Syndicate/Mixer/CH\(channel)/Volume", [.float(level)]))
    }

    /// The Volume levels sent to `channel`, in order.
    static func sentVolumes(_ rig: Rig, channel: Int = 1) -> [Float] {
        rig.osc.sent.compactMap { message in
            guard message.address == "/Syndicate/Mixer/CH\(channel)/Volume", case .float(let level)? = message.arguments.first else { return nil }
            return level
        }
    }

    static func seeks(_ rig: Rig) -> [OSCMessage] { rig.osc.sent.filter { $0.address.hasSuffix("/WaveformSeek") } }

    @Test("Shift held at touch-down: a swipe of half the strip moves the fader half its range from Syndicate's level, and seeks nothing")
    func halfSwipe() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)
        let sent = Self.sentVolumes(rig)
        #expect(abs((sent.last ?? 0) - 0.75) < 0.001, "sent \(sent)")
        #expect(Self.seeks(rig).isEmpty)
    }

    @Test("Without Shift the strip still seeks, and moves no fader")
    func withoutShiftSeeks() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(!Self.seeks(rig).isEmpty)
    }

    @Test("A touch with no travel sends nothing, even when the strip repeats where the finger is")
    func noTravel() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 4000)
        Self.at(rig, 4000)
        Self.touch(rig, false)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(Self.seeks(rig).isEmpty)
    }

    @Test("Clamped at both ends, and travel past an end isn't stored up: coming back moves the fader at once")
    func clamped() throws {
        let rig = try C.started()
        Self.volume(rig, 0.75)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)    // +0.5 from 0.75: past the top
        Self.at(rig, 12288)   // further past it
        Self.at(rig, 8192)    // back by a quarter: from the top, not from where the finger went
        let sent = Self.sentVolumes(rig)
        #expect(sent.count == 2 && sent[0] == 1.0 && abs(sent[1] - 0.75) < 0.001, "sent \(sent)")
        Self.at(rig, 0)
        Self.at(rig, 0)
        #expect(abs((Self.sentVolumes(rig).last ?? -1) - 0.25) < 0.001)
    }

    @Test("The mode is fixed at touch-down: Shift let go mid-touch stays a fader move, with no track jump under the finger")
    func shiftLetGo() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.shift(rig, false)
        Self.at(rig, 4096)
        Self.touch(rig, false)
        #expect(Self.sentVolumes(rig).count == 1)
        #expect(Self.seeks(rig).isEmpty)
    }

    @Test("The mode is fixed at touch-down: Shift pressed mid-touch leaves the touch a seek, and moves no fader")
    func shiftPressedMidTouch() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.shift(rig, true)
        Self.at(rig, 4096)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(Self.seeks(rig).count == 2)
    }

    @Test("With no Volume from Syndicate the touch does nothing: no fader move, no seek")
    func unknownLevel() throws {
        let rig = try C.started()
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(Self.seeks(rig).isEmpty)
    }

    @Test("With no Volume from Syndicate, the next touch counts from the level the last one sent")
    func fromLastSent() throws {
        let rig = try C.started()
        // Known once (a Resend), then the Volume box goes off: nothing more comes back.
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 4096)    // to 0.5
        Self.touch(rig, false)
        Self.touch(rig, true)
        Self.at(rig, 8192)
        Self.at(rig, 12288)   // a quarter more: 0.75
        let sent = Self.sentVolumes(rig)
        #expect(abs((sent.last ?? 0) - 0.75) < 0.001, "sent \(sent)")
    }

    @Test("Another deck layer moves that deck's channel, from that channel's own level")
    func layerChange() throws {
        let rig = try C.started()
        Self.volume(rig, channel: 1, 0.25)
        Self.volume(rig, channel: 2, 0.5)
        rig.coordinator.setDeck(2, controller: 0)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 4096)
        let sent = Self.sentVolumes(rig, channel: 2)
        #expect(abs((sent.last ?? 0) - 0.75) < 0.001, "sent \(sent)")
        #expect(Self.sentVolumes(rig, channel: 1).isEmpty)
    }

    @Test("During a touch Syndicate's echoes are ignored, a late one too: the fader goes by the travel, and can't fight itself")
    func echoesIgnored() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 2048)        // to 0.375
        Self.at(rig, 4096)        // to 0.5
        Self.volume(rig, 0.375)   // the echo of the first, arriving late
        Self.at(rig, 6144)        // to 0.625, not 0.375 + an eighth
        Self.touch(rig, false)
        Self.touch(rig, true)
        Self.at(rig, 6144)
        Self.at(rig, 8192)        // the next touch starts where this one left it: 0.75
        let sent = Self.sentVolumes(rig)
        #expect(sent.count == 4, "sent \(sent)")
        #expect(abs(sent[2] - 0.625) < 0.001 && abs(sent[3] - 0.75) < 0.001, "sent \(sent)")
    }

    static let jump = #"{ "needle": { "shift_fader_mode": "jump" } }"#

    @Test("Jump: touching the strip's midpoint with Shift sets the fader to half, with no travel and no level from Syndicate")
    func jumpMidpoint() throws {
        let rig = try C.started(Self.jump)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 8192)
        #expect(Self.sentVolumes(rig).count == 1 && abs((Self.sentVolumes(rig).first ?? 0) - 0.5) < 0.001, "sent \(Self.sentVolumes(rig))")
        Self.at(rig, 16383)   // and follows the finger: the top is the fader's top
        Self.at(rig, 0)
        #expect(Self.sentVolumes(rig).suffix(2) == [1.0, 0.0])
        #expect(Self.seeks(rig).isEmpty)
    }

    @Test("needle.shift_fader false: Shift + the strip seeks as it always has, and moves no fader")
    func off() throws {
        let rig = try C.started(#"{ "needle": { "shift_fader": false } }"#)
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(!Self.seeks(rig).isEmpty)
    }

    @Test("Relative needs Syndicate's Volume, so the health check asks for it; off, or in jump, it isn't asked for")
    func volumeSubscription() throws {
        #expect(try C.started().coordinator.status.requiredSubscriptions.contains(.mixerVolume))
        #expect(try !C.started(#"{ "needle": { "shift_fader": false } }"#).coordinator.status.requiredSubscriptions.contains(.mixerVolume))
        #expect(try !C.started(Self.jump).coordinator.status.requiredSubscriptions.contains(.mixerVolume))
    }

    @Test("Settings' choice of jump applies from the next touch, with no relaunch; a touch already down keeps its mode")
    func settingNextTouch() throws {
        let rig = try C.started()
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        rig.coordinator.apply(.setStripFader(StripFaderSetting(mode: .jump)))
        Self.at(rig, 4096)                    // still relative: 0.25 + a quarter
        #expect(abs((Self.sentVolumes(rig).last ?? 0) - 0.5) < 0.001)
        Self.touch(rig, false)
        rig.osc.sent.removeAll()
        Self.touch(rig, true)
        Self.at(rig, 16383)                   // jump: straight to the top, no travel
        #expect(Self.sentVolumes(rig) == [1.0])
        #expect(!rig.coordinator.status.requiredSubscriptions.contains(.mixerVolume))
    }

    @Test("Settings' off: Shift + the strip seeks, whatever the profile says, and Volume isn't asked for")
    func settingOff() throws {
        let rig = try C.started()
        rig.coordinator.apply(.setStripFader(StripFaderSetting(enabled: false)))
        Self.volume(rig, 0.25)
        Self.shift(rig, true)
        Self.touch(rig, true)
        Self.at(rig, 0)
        Self.at(rig, 8192)
        #expect(Self.sentVolumes(rig).isEmpty)
        #expect(!Self.seeks(rig).isEmpty)
        #expect(!rig.coordinator.status.requiredSubscriptions.contains(.mixerVolume))
    }
}
