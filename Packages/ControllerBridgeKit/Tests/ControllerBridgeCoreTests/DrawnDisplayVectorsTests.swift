import Foundation
@testable import ControllerBridgeCore
import Testing

/// The drawn jog display's shared message vectors (#455, #456): the Swift side encodes every host message in
/// tools/lc6000-display-fw/vectors/messages.json to its bytes, and reads every unit answer, as the C side does.
@Suite("Drawn display: the shared message vectors")
struct DrawnDisplayVectorsTests {
    static var file: [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/lc6000-display-fw/vectors/messages.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    static func bytes(_ entry: [String: Any]) -> [UInt8] {
        (entry["bytes"] as! String).split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    static func message(_ entry: [String: Any]) -> DrawnDisplay.Message? {
        let fields = entry["fields"] as! [String: Any]
        switch entry["kind"] as! String {
        case "capability": return .capability(version: fields["version"] as! Int)
        case "begin": return .begin(version: fields["version"] as! Int)
        case "end": return .end(version: fields["version"] as! Int)
        case "deck":
            return .deck(number: fields["number"] as! Int, color: fields["color"] as! [Int],
                         player: DrawnDisplay.Player(rawValue: UInt8(fields["player"] as! Int))!)
        case "state": return .state(DrawnDisplay.State(rawValue: UInt8(fields["flags"] as! Int)))
        case "beat": return .beat(fields["beat"] as! Int)
        case "needle": return .needle(fields["angle"] as! Int)
        default: return nil
        }
    }

    @Test("Every host message in the file encodes to its bytes, and the file has begin, end, capability and deck")
    func hostMessagesEncode() {
        // Text and tempo (#458) have no Swift encoder yet: agent1's host side drops this skip when it lands.
        let entries = (Self.file["messages"] as! [[String: Any]]).filter {
            $0["direction"] as? String != "unit" && !["text", "tempo"].contains($0["kind"] as? String ?? "")
        }
        #expect(Set(entries.map { $0["kind"] as! String }).isSuperset(of: ["begin", "end", "capability", "deck", "state", "beat", "needle"]))
        for entry in entries {
            let message = Self.message(entry)
            #expect(message != nil, "\(entry["name"]!): unknown kind")
            #expect(message?.bytes == Self.bytes(entry), "\(entry["name"]!)")
        }
    }

    @Test("Every unit answer in the file reads as its version; every malformed one reads as nothing")
    func unitAnswersDecode() {
        let answers = (Self.file["messages"] as! [[String: Any]]).filter { $0["direction"] as? String == "unit" }
        #expect(!answers.isEmpty)
        for entry in answers {
            let version = (entry["fields"] as! [String: Any])["version"] as! Int
            #expect(DrawnDisplay.answer(Self.bytes(entry)) == version, "\(entry["name"]!)")
        }
        let bad = (Self.file["invalid"] as! [[String: Any]]).filter { $0["direction"] as? String == "unit" }
        #expect(!bad.isEmpty)
        for entry in bad { #expect(DrawnDisplay.answer(Self.bytes(entry)) == nil, "\(entry["name"]!)") }
    }

    @Test("Syndicate's player types map to the wire's: empty, track, OSC clip, MIDI clip, sequencer, other")
    func playerTypes() {
        #expect(DrawnDisplay.Player(playerType: nil) == .empty)
        #expect(DrawnDisplay.Player(playerType: "empty") == .empty)
        #expect(DrawnDisplay.Player(playerType: "track") == .track)
        #expect(DrawnDisplay.Player(playerType: "OSC Clip") == .oscClip)
        #expect(DrawnDisplay.Player(playerType: "midiclip") == .midiClip)
        #expect(DrawnDisplay.Player(playerType: "Sequencer") == .sequencer)
        #expect(DrawnDisplay.Player(playerType: "Automation") == .other)
    }

    @Test("Every message goes out under our one command byte, never one Denon's firmware acts on (#466: 0F, 10 and 72; 78 and 79 write its settings flash)")
    func oneCommandByte() {
        let messages: [DrawnDisplay.Message] = [
            .capability(version: 1), .begin(version: 1), .end(version: 127),
            .deck(number: 4, color: [255, 255, 255], player: .other), .deck(number: 1, color: [], player: .empty), .state([.loaded, .stale]), .beat(0), .needle(16383),
        ]
        for message in messages { #expect(message.bytes[6] == DrawnDisplay.command) }
        #expect(![0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x72, 0x78, 0x79, 0x7C, 0x7F].contains(DrawnDisplay.command))
    }
}
