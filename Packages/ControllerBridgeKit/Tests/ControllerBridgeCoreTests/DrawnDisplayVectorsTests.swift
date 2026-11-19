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
        default: return nil
        }
    }

    @Test("Every host message in the file encodes to its bytes, and the file has begin, end, capability and deck")
    func hostMessagesEncode() {
        let entries = (Self.file["messages"] as! [[String: Any]]).filter { $0["direction"] as? String != "unit" }
        #expect(Set(entries.map { $0["kind"] as! String }).isSuperset(of: ["begin", "end", "capability", "deck"]))
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
}
