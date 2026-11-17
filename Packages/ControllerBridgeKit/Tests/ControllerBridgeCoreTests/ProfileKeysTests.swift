import Foundation
@testable import ControllerBridgeCore
import Testing

/// The profile key table (#382): every key a mapping takes, declared once, with its kind, the LC6000's value, and its
/// range, choices or list length. Pinned here to what the checker does, through its public interface.
@Suite("Profile key table")
struct ProfileKeysTests {
    static let lc6000 = try! OrderedJSON(parsing: Mapping.defaultJSON())

    /// A partial mapping with `value` at `pattern` (a list item's index written `[]`), and the path a problem names.
    static func document(_ pattern: String, _ value: OrderedJSON) -> (json: Data, path: String) {
        var concrete = "", prefix = ""
        func build(_ parts: ArraySlice<Substring>) -> OrderedJSON {
            guard let part = parts.first else { return value }
            let isList = part.hasSuffix("[]")
            let name = isList ? String(part.dropLast(2)) : String(part)
            let listKey = prefix.isEmpty ? name : "\(prefix).\(name)"
            prefix += (prefix.isEmpty ? "" : ".") + part
            concrete += (concrete.isEmpty ? "" : ".") + name + (isList ? "[0]" : "")
            let inner = build(parts.dropFirst())
            // A list as long as its key needs (a color takes 3), so the length isn't what's refused.
            let length = max(1, ProfileKeys.key(listKey)?.count?.lowerBound ?? 1)
            return .object([(name, isList ? .array(Array(repeating: inner, count: length)) : inner)])
        }
        let doc = build(pattern.split(separator: ".")[...])
        return (Data(text(doc).utf8), concrete)
    }

    /// The checker's problems at `path`, leaving out a duplicate number (another key's concern).
    static func problems(_ pattern: String, _ value: OrderedJSON) -> [String] {
        let (json, path) = document(pattern, value)
        return Mapping.problems(in: json).filter { $0.hasPrefix("\(path): ") && !$0.contains(" is also ") }
    }

    static func number(_ n: Double, whole: Bool) -> OrderedJSON { .number(n, isInteger: whole) }

    /// JSON text for a value (the test's own writer).
    static func text(_ value: OrderedJSON) -> String {
        switch value {
        case .object(let pairs): "{" + pairs.map { "\"\($0.key)\": " + text($0.value) }.joined(separator: ", ") + "}"
        case .array(let items): "[" + items.map(text).joined(separator: ", ") + "]"
        case .string(let s): "\"\(s)\""
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        case .number(let n, let whole): whole ? String(Int(n)) : String(n)
        }
    }

    @Test("Each key with an LC6000 value has the LC6000's value and kind, from the bundled profile")
    func lc6000Values() {
        for key in ProfileKeys.all {
            guard let expected = key.lc6000 else { continue }
            let found = Self.value(at: key.path, in: Self.lc6000)
            if key.kind == .object {
                if case .object? = found {} else { Issue.record("\(key.path): not an object in the LC6000's mapping") }
            } else {
                #expect(found == (try? OrderedJSON(parsing: Data(expected.utf8))), "\(key.path)")
            }
        }
    }

    @Test("Each key's kind is what the checker asks for: another kind is refused, naming the key's kind")
    func kinds() {
        for key in ProfileKeys.all {
            let wrong: OrderedJSON = key.kind == .bool ? .string("x") : .bool(true)
            let found = Self.problems(key.path, wrong)
            #expect(found.count == 1 && found[0].hasSuffix("expected \(key.kind.words), got \(Mapping.describe(wrong))"),
                    "\(key.path): \(found)")
        }
    }

    @Test("Each range's ends are allowed, and one past either end is refused")
    func ranges() {
        for key in ProfileKeys.all {
            guard let range = key.range else { continue }
            let whole = key.kind == .wholeNumber
            let step = whole ? 1.0 : 0.001
            #expect(Self.problems(key.path, Self.number(range.lowerBound, whole: whole)) == [], "\(key.path) low")
            #expect(Self.problems(key.path, Self.number(range.upperBound, whole: whole)) == [], "\(key.path) high")
            #expect(Self.problems(key.path, Self.number(range.lowerBound - step, whole: whole)).first?.contains("out of range") == true,
                    "\(key.path) below")
            #expect(Self.problems(key.path, Self.number(range.upperBound + step, whole: whole)).first?.contains("out of range") == true,
                    "\(key.path) above")
        }
    }

    @Test("Each key's choices are allowed, and anything else is refused")
    func choices() {
        for key in ProfileKeys.all {
            for choice in key.choices {
                #expect(Self.problems(key.path, .string(choice)) == [], "\(key.path) \(choice)")
            }
            if !key.choices.isEmpty {
                #expect(Self.problems(key.path, .string("nope")).first?.contains("isn't one of") == true, "\(key.path)")
            }
            for choice in key.numberChoices {
                #expect(Self.problems(key.path, Self.number(choice, whole: true)) == [], "\(key.path) \(choice)")
            }
            if !key.numberChoices.isEmpty {
                #expect(Self.problems(key.path, Self.number(1, whole: true)).first?.contains("isn't one of") == true, "\(key.path)")
            }
        }
    }

    @Test("Each list's length limits: the ends are allowed, one past either is refused")
    func counts() {
        for key in ProfileKeys.all {
            guard let count = key.count, let item = ProfileKeys.all.first(where: { $0.path == key.path + "[]" }) else { continue }
            let sample: OrderedJSON = item.kind == .object ? .object([]) : item.kind == .text ? .string(item.choices.first ?? "x")
                : Self.number(item.range?.lowerBound ?? 0, whole: true)
            func list(_ n: Int) -> OrderedJSON { .array(Array(repeating: sample, count: n)) }
            #expect(Self.problems(key.path, list(count.lowerBound)).filter { $0.contains("expected") } == [], "\(key.path) low")
            #expect(Self.problems(key.path, list(count.lowerBound - 1)).first?.contains("expected") == true, "\(key.path) below")
            if count.upperBound < Int.max {
                #expect(Self.problems(key.path, list(count.upperBound)).filter { $0.contains("expected") } == [], "\(key.path) high")
                #expect(Self.problems(key.path, list(count.upperBound + 1)).first?.contains("expected") == true, "\(key.path) above")
            }
        }
    }

    /// The value at a key pattern in a document: a list item's `[]` is its first item.
    static func value(at pattern: String, in document: OrderedJSON) -> OrderedJSON? {
        var current: OrderedJSON? = document
        for part in pattern.split(separator: ".") {
            let isList = part.hasSuffix("[]")
            current = current?[String(isList ? part.dropLast(2) : part)]
            if isList {
                guard case .array(let items)? = current, let first = items.first else { return nil }
                current = first
            }
        }
        return current
    }
}
