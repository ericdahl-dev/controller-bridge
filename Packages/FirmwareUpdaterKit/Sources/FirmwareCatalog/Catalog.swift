import Foundation
import FirmwareModel

/// A deck panel firmware image the app carries: its version, the build (git SHA) it was made from, and the file.
public struct PanelFirmware: Sendable, Hashable {
    public let version: FirmwareVersion
    public let sha: String
    public let image: URL
}

public enum CatalogError: Error, Equatable {
    case badVersion(String)
}

/// The firmware the app ships with, read from a folder holding `catalog.json` and the files it names. No network.
public struct Catalog: Sendable {
    private let panel: [PanelFirmware]

    public init(directory: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: directory.appending(path: "catalog.json")))
        panel = try file.panel.map { entry in
            guard let version = FirmwareVersion(entry.version) else { throw CatalogError.badVersion(entry.version) }
            return PanelFirmware(version: version, sha: entry.sha, image: directory.appending(path: entry.image))
        }
    }

    /// The highest panel version in the catalog, or nil if it carries none.
    public func newestPanel() -> PanelFirmware? {
        panel.max { $0.version < $1.version }
    }

    private struct File: Decodable {
        struct Panel: Decodable { let version: String; let sha: String; let image: String }
        let panel: [Panel]
    }
}
