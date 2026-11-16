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
    /// A device whose name contains one of these never gets this profile, even if a hint matches: a controller's
    /// other port that sends no controls, such as the LC6000's "…LC6000 PRIME WD" (#99).
    public var excludeHints: [String] = []
    public var mapping: Mapping

    public init(id: String, name: String, deviceHints: [String], mapping: Mapping) {
        self.id = id
        self.name = name
        self.deviceHints = deviceHints
        self.mapping = mapping
    }

    /// The profile for a device name: the one whose matching hint is longest, so a more specific profile wins.
    /// On a tie, the first listed profile wins.
    static func matching(_ deviceName: String, in profiles: [ControllerProfile]) -> ControllerProfile? {
        var best: (profile: ControllerProfile, hintLength: Int)?
        for candidate in candidates(deviceName, in: profiles) where candidate.hintLength > (best?.hintLength ?? -1) {
            best = candidate
        }
        return best?.profile
    }

    /// Every profile with a hint in the device name (substring, ignoring case), with its longest matching hint's length.
    static func candidates(_ deviceName: String, in profiles: [ControllerProfile]) -> [(profile: ControllerProfile, hintLength: Int)] {
        let name = deviceName.lowercased()
        return profiles.compactMap { profile in
            if profile.excludeHints.contains(where: { name.contains($0.lowercased()) }) { return nil }
            return profile.deviceHints.filter { name.contains($0.lowercased()) }.map(\.count).max().map { (profile, $0) }
        }
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
        excludeHints = header.excludeHints ?? []
        // A whole profile: duplicates among its own keys only (#251).
        mapping = try Mapping.checked(Self.mappingJSON(of: data), whole: true)
    }

    private struct Header: Decodable {
        var id: String
        var name: String
        var deviceHints: [String]
        var excludeHints: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name
            case deviceHints = "device_hints"
            case excludeHints = "exclude_hints"
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
