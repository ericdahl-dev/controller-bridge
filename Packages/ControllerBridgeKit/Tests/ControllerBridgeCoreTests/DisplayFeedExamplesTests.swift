import Foundation
@testable import ControllerBridgeCore
import Testing

/// The display feed's shared examples (#490 seam 3, #616): tools/deck-panel/feed/examples.json says, for each deck
/// state, the messages the feed sends for it. This walks it on the Swift side; the panel core's test (#619) walks the
/// same file, so the two can't drift. A key this walker doesn't know (a later field, #617) is left for its own test.
@Suite("Display feed: the shared examples")
struct DisplayFeedExamplesTests {
    static var file: [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/deck-panel/feed/examples.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    static var cases: [[String: Any]] { file["cases"] as! [[String: Any]] }

    /// One expected message: its type is the OSC type tag itself, i, f or s.
    static func message(_ entry: [String: Any]) -> OSCMessage? {
        let address = entry["address"] as! String
        switch entry["type"] as! String {
        case "i": return OSCMessage(address, [.int(Int32(entry["value"] as! Int))])
        case "f": return OSCMessage(address, [.float((entry["value"] as! NSNumber).floatValue)])
        case "s": return OSCMessage(address, [.string(entry["value"] as! String)])
        default: return nil
        }
    }

    static func deck(_ state: [String: Any]) -> DisplayFeed.Deck {
        DisplayFeed.Deck(number: state["deck"] as! Int, color: state["color"] as! [Int], loaded: state["loaded"] as? Bool ?? false,
                         title: state["title"] as? String ?? "", artist: state["artist"] as? String ?? "",
                         key: state["key"] as? String ?? "", bpm: state["bpm"] as? Double ?? 0, tempo: state["tempo"] as? Double ?? 0)
    }

    @Test("The file's prefix is the feed's, and it has a loaded deck, an empty one and non-ASCII text")
    func fileShape() {
        #expect(Self.file["prefix"] as? String == DisplayFeed.prefix)
        let names = Self.cases.map { $0["name"] as! String }
        #expect(names.count >= 3)
        #expect(Self.cases.contains { (($0["state"] as! [String: Any])["title"] as? String ?? "").isEmpty })
        #expect(Self.cases.contains { (($0["state"] as! [String: Any])["title"] as? String ?? "").utf8.count
            > (($0["state"] as! [String: Any])["title"] as? String ?? "").count })
    }

    @Test("Each case: turned on with that deck in front, the feed sends exactly its messages, in order, each with one value under the prefix")
    func everyCaseSends() {
        for example in Self.cases {
            let name = example["name"] as! String
            let expected = (example["messages"] as! [[String: Any]]).map(Self.message)
            #expect(!expected.contains(nil), "\(name): a type that isn't i, f or s")
            let sender = Rig.FakeOSC(), feed = DisplayFeed()
            feed.attach(sender)
            feed.set(DisplayFeedSettings(enabled: true, host: "192.168.1.40", port: 9100))
            feed.update(Self.deck(example["state"] as! [String: Any]))
            #expect(sender.sent == expected.compactMap { $0 }, "\(name)")
            #expect(sender.sent.allSatisfy { $0.address.hasPrefix(DisplayFeed.prefix) && $0.arguments.count == 1 }, "\(name)")
        }
    }
}
