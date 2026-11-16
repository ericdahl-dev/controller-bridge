import Foundation

extension ControllerProfile {
    /// The fields of a profile file, with an example value of each kind, for the import check.
    private static let headerSchema: OrderedJSON = .object([
        ("id", .string("")), ("name", .string("")), ("device_hints", .array([.string("")])), ("mapping", .object([])),
    ])

    /// A user's mapping file, applied over a bundled profile (#24). Every field is optional: `id`, if present, must
    /// name a bundled profile, and a missing `id` means `active`. `name` and `device_hints` replace the bundled ones;
    /// `mapping` merges over the bundled body, the Python way. Throws every problem at once, in document order.
    public static func importing(_ data: Data, bundled: [ControllerProfile], active: String) throws -> ControllerProfile {
        let document: OrderedJSON
        do { document = try OrderedJSON(parsing: data) } catch { throw MappingError.invalid(["\(error)"]) }
        if let problem = Mapping.kindProblem(document, expected: headerSchema) { throw MappingError.invalid(["file: \(problem)"]) }
        guard case .object(let fields) = document else { throw MappingError.invalid(["file: expected an object"]) }

        var problems: [String] = []
        for (key, value) in fields {
            guard let expected = headerSchema[key] else { problems.append("\(key): unknown key"); continue }
            if let problem = Mapping.kindProblem(value, expected: expected) { problems.append("\(key): \(problem)"); continue }
            switch (key, value) {
            case let ("id", .string(id)) where !bundled.contains(where: { $0.id == id }):
                problems.append("id: \"\(id)\" isn't a bundled profile (\(bundled.map(\.id).joined(separator: ", ")))")
            case let ("device_hints", .array(hints)):
                for (index, hint) in hints.enumerated() {
                    if let problem = Mapping.kindProblem(hint, expected: .string("")) { problems.append("device_hints[\(index)]: \(problem)") }
                }
            case ("mapping", _):
                problems += Mapping.problems(in: value).map { "mapping.\($0)" }
            default:
                break
            }
        }
        guard problems.isEmpty else { throw MappingError.invalid(problems) }

        let id = if case .string(let id)? = document["id"] { id } else { active }
        guard var profile = bundled.first(where: { $0.id == id }) else {
            throw MappingError.invalid(["id: \"\(id)\" isn't a bundled profile"])
        }
        if case .string(let name)? = document["name"] { profile.name = name }
        if case .array(let hints)? = document["device_hints"] {
            profile.deviceHints = hints.compactMap { if case .string(let hint) = $0 { hint } else { nil } }
        }
        if let mapping = document["mapping"] {
            let base = try OrderedJSON(parsing: mappingJSON(of: bundledFile(id)))
            profile.mapping = try Mapping.checked(Mapping.merge(base, mapping).data())
        }
        return profile
    }
}

extension OrderedJSON {
    /// Back to JSON, keeping key order.
    func data() -> Data {
        Data(text().utf8)
    }

    private func text() -> String {
        switch self {
        case .object(let pairs): "{" + pairs.map { "\(Self.quoted($0.key)):\($0.value.text())" }.joined(separator: ",") + "}"
        case .array(let items): "[" + items.map { $0.text() }.joined(separator: ",") + "]"
        case .string(let s): Self.quoted(s)
        case .number(let n, _): n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        }
    }

    private static func quoted(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
