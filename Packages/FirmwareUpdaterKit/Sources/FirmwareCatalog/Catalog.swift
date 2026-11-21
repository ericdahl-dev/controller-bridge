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

/// What the app offers a deck panel.
public enum PanelOffer: Sendable, Hashable {
    /// The panel runs an older build the app shipped; this is newer.
    case update(PanelFirmware)
    /// The panel runs the newest build.
    case upToDate
    /// The panel runs a build the app doesn't know (a dev build, or newer than the app): offered with a note.
    case unknownBuild(PanelFirmware)
    /// The app carries no panel firmware.
    case nothing
}

extension Catalog {
    public func offer(for build: PanelBuild) -> PanelOffer {
        guard let newest = newestPanel() else { return .nothing }
        guard let shipped = panel.first(where: { Self.sameBuild($0.sha, build.sha) }) else { return .unknownBuild(newest) }
        return shipped.version < newest.version ? .update(newest) : .upToDate
    }

    /// Short and long forms of one SHA name the same build: the shorter must start the longer.
    static func sameBuild(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        return a.count <= b.count ? b.hasPrefix(a) : a.hasPrefix(b)
    }
}
