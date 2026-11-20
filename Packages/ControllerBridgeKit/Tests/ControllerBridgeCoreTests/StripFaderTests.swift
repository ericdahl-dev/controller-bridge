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
}
