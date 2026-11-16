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
                // With no usable hint, no device matches after the next replug or launch (#93).
                if hints.isEmpty { problems.append("device_hints: needs at least one device name") }
                for (index, hint) in hints.enumerated() {
                    if let problem = Mapping.kindProblem(hint, expected: .string("")) {
                        problems.append("device_hints[\(index)]: \(problem)")
                    } else if case .string(let text) = hint, text.trimmingCharacters(in: .whitespaces).isEmpty {
                        problems.append("device_hints[\(index)]: can't be empty")
                    }
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
            profile.mapping = try Mapping.checked(Mapping.merge(base, mapping.removing(settingsOwned)).data())
        }
        return profile
    }
}

extension ControllerProfile {
    /// The whole profile as a file (#24): id, name, hints and the full mapping, in the bundled file's key order, so
    /// importing it gives this profile back.
    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        let encoded = try OrderedJSON(parsing: encoder.encode(mapping))
        let schema = try OrderedJSON(parsing: Mapping.defaultJSON())
        let file: OrderedJSON = .object([
            ("id", .string(id)),
            ("name", .string(name)),
            ("device_hints", .array(deviceHints.map { .string($0) })),
            // Settings owns these (#93), so the file never carries values that would silently lose to it.
            ("mapping", encoded.ordered(like: schema).removing(Self.settingsOwned)),
        ])
        return file.data(pretty: true)
    }
}

extension OrderedJSON {
    /// The same JSON with object keys in `template`'s order; keys the template lacks keep their order, after.
    func ordered(like template: OrderedJSON) -> OrderedJSON {
        switch (self, template) {
        case let (.object(pairs), .object(templatePairs)):
            let rank = Dictionary(templatePairs.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
            let sorted = pairs.enumerated().sorted { a, b in
                (rank[a.element.key] ?? Int.max, a.offset) < (rank[b.element.key] ?? Int.max, b.offset)
            }.map(\.element)
            return .object(sorted.map { pair in (pair.key, template[pair.key].map { pair.value.ordered(like: $0) } ?? pair.value) })
        default:
            return self
        }
    }

    /// Back to JSON, keeping key order. Pretty: two-space indents, short lists of numbers on one line.
    func data(pretty: Bool = false) -> Data {
        Data((pretty ? prettyText(indent: "") + "\n" : text()).utf8)
    }

    private func prettyText(indent: String) -> String {
        let inner = indent + "  "
        switch self {
        case .object(let pairs) where !pairs.isEmpty:
            return "{\n" + pairs.map { "\(inner)\(Self.quoted($0.key)): \($0.value.prettyText(indent: inner))" }.joined(separator: ",\n")
                + "\n\(indent)}"
        case .array(let items) where items.contains(where: { if case .object = $0 { true } else { false } }):
            return "[\n" + items.map { inner + $0.prettyText(indent: inner) }.joined(separator: ",\n") + "\n\(indent)]"
        case .array(let items):
            return "[" + items.map { $0.text() }.joined(separator: ", ") + "]"
        default:
            return text()
        }
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

extension ControllerProfile {
    /// Mapping keys Settings owns (#93): the OSC addresses and ports, the deck and the MIDI channel. A file's values
    /// for them would silently lose to Settings, so an import doesn't apply them and an export doesn't write them.
    static let settingsOwned: [[String]] = [
        ["osc", "host"], ["osc", "port"], ["osc", "feedback_host"], ["osc", "feedback_port"], ["deck", "number"], ["midi", "channel"],
    ]

    /// The Settings-owned keys a file sets, as "mapping.osc.port", in document order, so the import can say they
    /// weren't applied.
    public static func settingsOwnedKeys(in data: Data) -> [String] {
        guard let document = try? OrderedJSON(parsing: data), let mapping = document["mapping"] else { return [] }
        var found: [String] = []
        if case .object(let sections) = mapping {
            for (section, value) in sections {
                guard case .object(let keys) = value else { continue }
                for (key, _) in keys where settingsOwned.contains([section, key]) { found.append("mapping.\(section).\(key)") }
            }
        }
        return found
    }
}

extension OrderedJSON {
    /// The object without the given section.key paths, and without a section that only had those; anything else
    /// unchanged.
    func removing(_ paths: [[String]]) -> OrderedJSON {
        guard case .object(let sections) = self else { return self }
        return .object(sections.compactMap { section, value in
            guard case .object(let keys) = value else { return (section, value) }
            let kept = keys.filter { !paths.contains([section, $0.key]) }
            return kept.isEmpty && !keys.isEmpty ? nil : (section, .object(kept))
        })
    }
}
