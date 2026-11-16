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
