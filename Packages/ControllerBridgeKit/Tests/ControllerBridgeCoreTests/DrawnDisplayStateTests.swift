@testable import ControllerBridgeCore
import Testing

/// What the chip knows, decoded from the drawn messages in Swift (#465), as dfw.c decodes them: the Diagnostics
/// preview draws from it, so it shows what the chip got.
@Suite("Drawn display: the chip's state, in Swift")
struct DrawnDisplayStateTests {
    typealias Vectors = DrawnDisplayVectorsTests
    static let begin = DrawnDisplay.Message.begin(version: 1).bytes
    static let deck3 = DrawnDisplay.Message.deck(number: 3, color: [0, 255, 0], player: .sequencer).bytes

    static func codes(_ hex: String) -> [UInt8] { hex.split(separator: " ").map { UInt8($0, radix: 16)! } }

    @Test("Every host message in the shared vectors decodes to its fields, after begin and a deck")
    func vectors() {
        let entries = (Vectors.file["messages"] as! [[String: Any]]).filter { $0["direction"] as? String != "unit" }
        for entry in entries {
            let name = entry["name"] as! String, fields = entry["fields"] as! [String: Any]
            var state = DrawnDisplayState()
            state.apply(Self.begin)
            state.apply(Self.deck3)
            state.apply(Vectors.bytes(entry))
            switch entry["kind"] as! String {
            case "capability", "begin", "end": continue
            case "deck":
                #expect(state.deck == DrawnDisplayState.Deck(number: fields["number"] as! Int, color: fields["color"] as! [Int],
                                                             player: DrawnDisplay.Player(rawValue: UInt8(fields["player"] as! Int))!),
                        "\(name)")
            case "state": #expect(state.flags.rawValue == UInt8(fields["flags"] as! Int), "\(name)")
            case "beat": #expect(state.beat == fields["beat"] as! Int, "\(name)")
            case "needle": #expect(state.needle == fields["angle"] as? Int, "\(name)")
            case "meter":
                #expect(state.meter?.level == fields["level"] as? Int && state.meter?.peak == fields["peak"] as? Int, "\(name)")
            case "text":
                let field = DrawnDisplay.TextField(rawValue: UInt8(fields["field"] as! Int))!
                #expect(state.texts[field] == Self.codes(fields["codes"] as? String ?? ""), "\(name)")
            case "tempo": #expect(state.tempo == fields["tenths"] as! Int, "\(name)")
            case "phase": #expect(state.phase == fields["offset"] as! Int, "\(name)")
            default: Issue.record("\(name): a kind the state doesn't decode")
            }
        }
    }
}
