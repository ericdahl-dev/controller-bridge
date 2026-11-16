import Foundation

/// A controller profile: a mapping with a name, and the MIDI device names it's for. A new controller is a new
/// profile file, not new code.
public struct ControllerProfile: Equatable, Sendable {
    /// Stable, for saved settings: "denon-lc6000-prime".
    public var id: String
    /// Shown in the menu: "Denon LC6000 PRIME".
    public var name: String
    /// A connected device whose name contains one of these, ignoring case, gets this profile.
    public var deviceHints: [String]
    public var mapping: Mapping

    public init(id: String, name: String, deviceHints: [String], mapping: Mapping) {
        self.id = id
        self.name = name
        self.deviceHints = deviceHints
        self.mapping = mapping
    }

    /// The profile for a device name: the one whose matching hint is longest, so a more specific profile wins.
    static func matching(_ deviceName: String, in profiles: [ControllerProfile]) -> ControllerProfile? {
        let name = deviceName.lowercased()
        let scored = profiles.compactMap { profile -> (ControllerProfile, Int)? in
            let lengths = profile.deviceHints.filter { name.contains($0.lowercased()) }.map(\.count)
            return lengths.max().map { (profile, $0) }
        }
        return scored.max { $0.1 < $1.1 }?.0
    }

    /// The profiles that ship with the app, in Resources/Profiles.
    public static let bundledIDs = ["denon-lc6000-prime"]

    public static func bundled() throws -> [ControllerProfile] {
        try bundledIDs.map { try ControllerProfile(decoding: bundledFile($0)) }
    }

    /// A profile file: `id`, `name`, `device_hints` and the `mapping` body.
    public init(decoding data: Data) throws {
        let header = try JSONDecoder().decode(Header.self, from: data)
        id = header.id
        name = header.name
        deviceHints = header.deviceHints
        mapping = try Mapping.checked(Self.mappingJSON(of: data))
    }

    private struct Header: Decodable {
        var id: String
        var name: String
        var deviceHints: [String]

        enum CodingKeys: String, CodingKey {
            case id, name
            case deviceHints = "device_hints"
        }
    }

    static func bundledFile(_ id: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Profiles") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    /// The `mapping` object of a profile file, as JSON on its own.
    static func mappingJSON(of profile: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: profile) as? [String: Any], let mapping = object["mapping"] else {
            throw CocoaError(.coderValueNotFound)
        }
        return try JSONSerialization.data(withJSONObject: mapping)
    }
}
