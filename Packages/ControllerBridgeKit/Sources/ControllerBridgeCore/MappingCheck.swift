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
        walk(document, schema: schema, path: [], into: &out)
        return out
    }

    /// The default mapping body, the schema every import is checked against.
    public static func defaultMappingJSON() throws -> Data { try defaultJSON() }

    private static func walk(_ value: OrderedJSON, schema: OrderedJSON, path: [String], into out: inout [String]) {
        guard case .object(let pairs) = value else { return }
        for (key, child) in pairs {
            let childPath = path + [key]
            guard let expected = schema[key] else {
                out.append("\(childPath.joined(separator: ".")): unknown key")
                continue
            }
            walk(child, schema: expected, path: childPath, into: &out)
        }
    }
}
