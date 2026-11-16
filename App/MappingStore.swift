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

    /// The kept import, if there is one. What it means is decided by MappingLibrary (#94).
    static var saved: Data? { try? Data(contentsOf: file) }

    static func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Deletes the kept import. Nothing to delete isn't an error.
    static func remove() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
