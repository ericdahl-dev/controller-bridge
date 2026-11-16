// The imported mapping file (#24), kept in the app's Application Support (inside its sandbox container). Not
// unit-tested: the import check, merge and export are tested in ControllerBridgeKit; this only reads and writes the
// file, and is covered by the manual check in the PR.
import ControllerBridgeCore
import Foundation

enum MappingStore {
    /// The copy of the last accepted import. Absent means the bundled profiles run as shipped.
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mapping", isDirectory: true)
            .appendingPathComponent("imported.json")
    }

    /// The profiles to run at launch: the bundled ones, with the saved import applied. A saved file that no longer
    /// passes the check (say, after an app update) is ignored, and its problems are returned.
    static func profiles(bundled: [ControllerProfile]) -> (profiles: [ControllerProfile], problems: [String]) {
        guard let data = try? Data(contentsOf: file) else { return (bundled, []) }
        do {
            let imported = try ControllerProfile.importing(data, bundled: bundled, active: bundled[0].id)
            return (replacing(imported, in: bundled), [])
        } catch MappingError.invalid(let problems) {
            return (bundled, problems)
        } catch {
            return (bundled, ["\(error)"])
        }
    }

    static func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: file)
    }

    static var hasImport: Bool { FileManager.default.fileExists(atPath: file.path) }

    static func replacing(_ profile: ControllerProfile, in profiles: [ControllerProfile]) -> [ControllerProfile] {
        profiles.map { $0.id == profile.id ? profile : $0 }
    }
}
