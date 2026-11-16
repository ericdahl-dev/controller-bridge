import ControllerBridgeCore
import Foundation
import Testing

/// Which profiles run, and what Settings says about them, across imports, rejects, resets and launches (#94).
@Suite("Mapping library")
struct MappingLibraryTests {
    static let good = Data(#"{"name": "My LC6000", "mapping": {"notes": {"play": 60}}}"#.utf8)
    static let bad = Data(#"{"mapping": {"notes": {"paly": 1}}}"#.utf8)

    @Test("A rejected import changes nothing: same profiles, same 'in use' line, and every problem returned")
    func rejectedImport() throws {
        var library = MappingLibrary(bundled: try ControllerProfile.bundled(), saved: nil)
        let before = library
        #expect(library.importFile(Self.bad, named: "bad.json") == ["mapping.notes.paly: unknown key"])
        #expect(library == before)
        #expect(library.inUse == "Bundled default")
    }

    @Test("An accepted import runs the new profile and says so")
    func acceptedImport() throws {
        var library = MappingLibrary(bundled: try ControllerProfile.bundled(), saved: nil)
        #expect(library.importFile(Self.good, named: "mine.json") == [])
        #expect(library.profiles.first?.mapping.notes.buttons["play"] == 60)
        #expect(library.inUse == "Imported: My LC6000")
    }

    @Test("Reset goes back to the bundled profiles")
    func reset() throws {
        let bundled = try ControllerProfile.bundled()
        var library = MappingLibrary(bundled: bundled, saved: nil)
        _ = library.importFile(Self.good, named: "mine.json")
        library.reset()
        #expect(library.profiles == bundled)
        #expect(library.inUse == "Bundled default")
    }

    @Test("At launch a saved import runs; one that no longer passes the check is set aside with its problems")
    func launch() throws {
        let bundled = try ControllerProfile.bundled()
        let saved = MappingLibrary(bundled: bundled, saved: Self.good)
        #expect(saved.inUse == "Imported: My LC6000")
        #expect(saved.launchProblems == [])
        let stale = MappingLibrary(bundled: bundled, saved: Self.bad)
        #expect(stale.profiles == bundled)
        #expect(stale.inUse == "Bundled default")
        #expect(stale.launchProblems == ["mapping.notes.paly: unknown key"])
    }
}
