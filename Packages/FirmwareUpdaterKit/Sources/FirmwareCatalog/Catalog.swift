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
    private let lc6000: [LC6000PatchSet]

    public init(directory: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: directory.appending(path: "catalog.json")))
        panel = try file.panel.map { entry in
            guard let version = FirmwareVersion(entry.version) else { throw CatalogError.badVersion(entry.version) }
            return PanelFirmware(version: version, sha: entry.sha, image: directory.appending(path: entry.image))
        }
        lc6000 = file.lc6000.map { set in
            LC6000PatchSet(
                firmware: LC6000Firmware(wd: set.wd, tp: set.tp),
                entries: set.entries.map { LC6000Entry(kind: $0.kind, chip: $0.chip, file: directory.appending(path: $0.file)) })
        }
    }

    /// The highest panel version in the catalog, or nil if it carries none.
    public func newestPanel() -> PanelFirmware? {
        panel.max { $0.version < $1.version }
    }

    private struct File: Decodable {
        struct Panel: Decodable { let version: String; let sha: String; let image: String }
        struct Set: Decodable { let wd: String; let tp: String; let entries: [Entry] }
        struct Entry: Decodable { let kind: LC6000Entry.Kind; let chip: Chip; let file: String }
        let panel: [Panel]
        let lc6000: [Set]
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
        // A panel that reports its version (#695) is judged by it; the SHA list is for panels that report only a SHA.
        if let version = build.version { return version < newest.version ? .update(newest) : .upToDate }
        guard let shipped = panel.first(where: { Self.sameBuild($0.sha, build.sha) }) else { return .unknownBuild(newest) }
        return shipped.version < newest.version ? .update(newest) : .upToDate
    }

    /// Short and long forms of one SHA name the same build: the shorter must start the longer.
    static func sameBuild(_ a: String, _ b: String) -> Bool {
        let a = a.lowercased(), b = b.lowercased()
        return a.count <= b.count ? b.hasPrefix(a) : a.hasPrefix(b)
    }
}

public enum Chip: String, Sendable, Hashable, Decodable { case wd, tp }

/// One thing the app applies to an LC6000 chip. Only patch descriptions for now; a block built from this repo
/// is a second kind (#696).
public struct LC6000Entry: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, Decodable {
        /// Addresses and the few bytes replaced at each, for one stock firmware version. Never a vendor image.
        case patch
    }

    public let kind: Kind
    public let chip: Chip
    public let file: URL
}

/// The patches tested together on one pair of stock firmware versions.
public struct LC6000PatchSet: Sendable, Hashable {
    public let firmware: LC6000Firmware
    public let entries: [LC6000Entry]
}

extension Catalog {
    /// The patch set tested on exactly these firmware versions, or nil if none fits.
    public func patchSet(for firmware: LC6000Firmware) -> LC6000PatchSet? {
        lc6000.first { $0.firmware == firmware }
    }
}
