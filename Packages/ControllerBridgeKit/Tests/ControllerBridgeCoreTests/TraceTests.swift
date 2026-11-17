import Foundation
@testable import ControllerBridgeCore
import Testing

/// The debug trace (#395): what Debug builds write to os_log and to a rolling file, so an agent can read what the
/// controller, Syndicate and the jog display did without asking for a paste.
@Suite("Debug trace")
struct TraceTests {
    @Test("One line: UTC time to the millisecond, the category padded to 13, the text")
    func lineFormat() {
        let at = Date(timeIntervalSince1970: 1_763_332_863.123)   // 2025-11-16T22:41:03.123Z
        #expect(TraceLine.format(at: at, .oscIn, "/Syndicate/Deck/1/Playing 1")
            == "2025-11-16T22:41:03.123Z osc-in        /Syndicate/Deck/1/Playing 1")
        #expect(TraceLine.format(at: at, .subscriptions, "Cues: off")
            == "2025-11-16T22:41:03.123Z subscriptions Cues: off")
    }

    @Test("Each category's name, as os_log and the file use it")
    func categoryNames() {
        #expect(TraceCategory.allCases.map(\.rawValue) == [
            "midi-in", "midi-out", "osc-in", "osc-out", "jog-display", "coordinator", "capture", "quantize",
            "subscriptions", "error",
        ])
    }

    @Test("Streaming OSC (Position, BarRamp, Meter, …) at most 5 a second per address; the next kept one counts what was skipped")
    func sampler() {
        var sampler = StreamSampler()
        let position = "/Syndicate/Deck/1/Position"
        var kept: [String] = []
        // 100 a second for half a second: one every 10 ms.
        for i in 0..<50 {
            if let note = sampler.admit(position, at: Double(i) * 0.01) { kept.append(note) }
        }
        #expect(kept == ["", " (+19 skipped)", " (+19 skipped)"])
        // Another deck's Position is its own stream.
        let otherDeck = sampler.admit("/Syndicate/Deck/2/Position", at: 0.49)
        #expect(otherDeck == "")
    }

    @Test("Everything else always passes, unsampled")
    func nonStreaming() {
        var sampler = StreamSampler()
        var playing: [String?] = []
        for _ in 0..<10 { playing.append(sampler.admit("/Syndicate/Deck/1/Playing", at: 1.0)) }
        #expect(playing == Array(repeating: "", count: 10))
        let first = sampler.admit("/Syndicate/Mixer/CH1/Meter", at: 1.0)
        let soon = sampler.admit("/Syndicate/Mixer/CH1/Meter", at: 1.05)
        #expect(first == "")
        #expect(soon == nil, "Meter is streaming on the mixer too")
    }

    static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    @Test("The rolling file appends lines; past the cap it moves deckbridge.log to .1 and .1 to .2, keeping 3 files")
    func rolling() throws {
        let directory = try Self.tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = RollingLogFile(directory: directory, name: "deckbridge.log", cap: 20, keep: 3)
        for line in ["aaaaaaaaa", "bbbbbbbbb", "ccccccccc", "ddddddddd", "eeeeeeeee", "fffffffff", "ggggggggg"] {
            file.append(line)
        }
        let main = directory.appendingPathComponent("deckbridge.log")
        // Each line is 10 bytes with its newline; two fit under the 20-byte cap, the third rolls.
        #expect(Self.read(main) == "ggggggggg\n")
        #expect(Self.read(directory.appendingPathComponent("deckbridge.log.1")) == "eeeeeeeee\nfffffffff\n")
        #expect(Self.read(directory.appendingPathComponent("deckbridge.log.2")) == "ccccccccc\nddddddddd\n")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("deckbridge.log.3").path))
        #expect(file.url == main)
    }

    @Test("A missing folder is made; an existing file is appended to, not replaced")
    func appendsAcrossLaunches() throws {
        let directory = try Self.tempDirectory().appendingPathComponent("Logs/DeckBridge")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent()) }
        RollingLogFile(directory: directory, name: "deckbridge.log", cap: 1000, keep: 3).append("first launch")
        RollingLogFile(directory: directory, name: "deckbridge.log", cap: 1000, keep: 3).append("second launch")
        #expect(Self.read(directory.appendingPathComponent("deckbridge.log")) == "first launch\nsecond launch\n")
    }
}
