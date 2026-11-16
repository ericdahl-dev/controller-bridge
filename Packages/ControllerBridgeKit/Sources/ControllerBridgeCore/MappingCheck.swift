import Foundation

extension Mapping {
    /// Every problem in a mapping body (a whole mapping, or a partial one to merge over the default), named by key
    /// path, in document order (#24). The bundled default mapping is the schema. An empty list means it's usable.
    public static func problems(in json: Data) -> [String] {
        let document: OrderedJSON
        let schema: OrderedJSON
        do {
            document = try OrderedJSON(parsing: json)
            schema = try OrderedJSON(parsing: defaultJSON())
        } catch {
            return ["\(error)"]
        }
        var out: [String] = []
        walk(document, schema: schema, path: "", into: &out)
        return out
    }

    /// The default mapping body, the schema every import is checked against.
    public static func defaultMappingJSON() throws -> Data { try defaultJSON() }

    private static func walk(_ value: OrderedJSON, schema: OrderedJSON, path: String, into out: inout [String]) {
        if let problem = kindProblem(value, expected: schema) {
            out.append("\(path): \(problem)")
            return
        }
        if let problem = valueProblem(value, at: path) {
            out.append("\(path): \(problem)")
            return
        }
        switch (value, schema) {
        case let (.object(pairs), _):
            for (key, child) in pairs {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                guard let expected = schema[key] else {
                    out.append("\(childPath): unknown key")
                    continue
                }
                walk(child, schema: expected, path: childPath, into: &out)
            }
        case let (.array(items), .array(schemaItems)):
            guard let element = schemaItems.first else { return }
            for (index, item) in items.enumerated() {
                walk(item, schema: element, path: "\(path)[\(index)]", into: &out)
            }
        default:
            break
        }
    }

    /// What's wrong with a value's kind, measured against the default's value at the same path; nil when it fits.
    private static func kindProblem(_ value: OrderedJSON, expected: OrderedJSON) -> String? {
        let fits = switch (value, expected) {
        case (.object, .object), (.array, .array), (.string, .string), (.bool, .bool): true
        // A setting whose default is whole takes only whole numbers (2.0 is whole); a fractional one takes any.
        case let (.number(n, _), .number(_, isInteger)): !isInteger || n.rounded() == n
        default: false
        }
        guard !fits else { return nil }
        let wanted = switch expected {
        case .object: "an object"
        case .array: "a list"
        case .string: "text"
        case .bool: "true or false"
        case .number(_, let isInteger): isInteger ? "a whole number" : "a number"
        case .null: "nothing"
        }
        return "expected \(wanted), got \(describe(value))"
    }

    /// Ranges and choices, by key path. A list element's path ends in `[]`.
    private static let ranges: [String: ClosedRange<Double>] = {
        var table: [String: ClosedRange<Double>] = [
            "midi.channel": 1...16,
            "deck.number": 1...4,
            "notes.pads[]": 0...127,
            "jog.ccs[]": 0...127,
            "pitch.msb_cc": 0...127, "pitch.lsb_cc": 0...127,
            "needle.cc": 0...127, "needle.touch_note": 0...127,
            "browse.select_turn_cc": 0...127, "browse.auto_loop_size_cc": 0...127,
            "leds.pitch_center": 0...127, "leds.ring": 0...127,
        ]
        for color in ["ring_color", "roll_pad_color", "loop_pad_color"] { table["leds.\(color)[]"] = 0...255 }
        return table
    }()

    private static let colors: Set<String> = ["leds.ring_color", "leds.roll_pad_color", "leds.loop_pad_color"]

    private static let choices: [String: [String]] = [
        "leds.beat_pulse": LEDs.BeatPulse.allRawValues,
        "leds.stale_idle": LEDs.StaleIdle.allRawValues,
    ]

    /// A range, count or choice problem with a value of the right kind; nil when it's fine.
    private static func valueProblem(_ value: OrderedJSON, at path: String) -> String? {
        let pattern = path.replacingOccurrences(of: #"\[\d+\]"#, with: "[]", options: .regularExpression)
        switch value {
        case .number(let n, _):
            // Every note is 0–127, whatever its button is called.
            let range = ranges[pattern] ?? (pattern.hasPrefix("notes.") ? 0...127 : nil)
            if let range, !range.contains(n) {
                return "\(describe(value)) is out of range, expected \(Int(range.lowerBound))-\(Int(range.upperBound))"
            }
        case .array(let items) where colors.contains(pattern) && items.count != 3:
            return "expected 3 values, got \(items.count)"
        case .string(let text):
            if let allowed = choices[pattern], !allowed.contains(text) {
                return "\(describe(value)) isn't one of \(allowed.joined(separator: ", "))"
            }
        default:
            break
        }
        return nil
    }

    /// A value as the user wrote it, for a problem message.
    static func describe(_ value: OrderedJSON) -> String {
        switch value {
        case .object: "an object"
        case .array: "a list"
        case .string(let text): "\"\(text)\""
        case .bool(let flag): flag ? "true" : "false"
        case .null: "null"
        case .number(let n, _): n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        }
    }
}

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var allRawValues: [String] { allCases.map(\.rawValue) }
}
