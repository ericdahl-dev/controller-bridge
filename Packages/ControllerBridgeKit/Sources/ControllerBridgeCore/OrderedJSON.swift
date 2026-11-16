import Foundation

/// JSON that keeps object keys in document order, so the mapping check can report problems in the order a user
/// reads their file. `JSONSerialization` loses that order.
indirect enum OrderedJSON: Equatable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The number and whether it was written without a fraction or exponent.
    case number(Double, isInteger: Bool)
    case bool(Bool)
    case null

    static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)): x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(x), .array(y)): x == y
        case let (.string(x), .string(y)): x == y
        case let (.number(x, i), .number(y, j)): x == y && i == j
        case let (.bool(x), .bool(y)): x == y
        case (.null, .null): true
        default: false
        }
    }

    subscript(key: String) -> OrderedJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    struct ParseError: Error, CustomStringConvertible {
        var offset: Int
        var description: String { "not valid JSON near byte \(offset)" }
    }

    init(parsing data: Data) throws {
        var parser = Parser(bytes: Array(data))
        self = try parser.value()
        parser.skipSpace()
        guard parser.index == parser.bytes.count else { throw ParseError(offset: parser.index) }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
        }

        mutating func value() throws -> OrderedJSON {
            skipSpace()
            guard index < bytes.count else { throw ParseError(offset: index) }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard index + w.count <= bytes.count, Array(bytes[index..<index + w.count]) == w else { throw ParseError(offset: index) }
            index += w.count
        }

        mutating func object() throws -> OrderedJSON {
            index += 1
            var pairs: [(key: String, value: OrderedJSON)] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError(offset: index) }
                let key = try string()
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError(offset: index) }
                index += 1
                pairs.append((key, try value()))
                skipSpace()
                guard index < bytes.count else { throw ParseError(offset: index) }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw ParseError(offset: index)
            }
        }

        mutating func array() throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                items.append(try value())
                skipSpace()
                guard index < bytes.count else { throw ParseError(offset: index) }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError(offset: index)
            }
        }

        /// A JSON string; escapes are decoded by Foundation, which parses the quoted fragment exactly.
        mutating func string() throws -> String {
            let start = index
            index += 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                if bytes[index] == UInt8(ascii: "\\") { index += 1 }
                index += 1
            }
            guard index < bytes.count else { throw ParseError(offset: start) }
            index += 1
            let fragment = Data(bytes[start..<index])
            guard let text = try? JSONSerialization.jsonObject(with: fragment, options: .fragmentsAllowed) as? String else {
                throw ParseError(offset: start)
            }
            return text
        }

        mutating func number() throws -> OrderedJSON {
            let start = index
            var isInteger = true
            while index < bytes.count, let c = Optional(bytes[index]),
                  c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c)
                    || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
                if c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") { isInteger = false }
                index += 1
            }
            guard index > start, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw ParseError(offset: start)
            }
            return .number(value, isInteger: isInteger)
        }
    }
}
