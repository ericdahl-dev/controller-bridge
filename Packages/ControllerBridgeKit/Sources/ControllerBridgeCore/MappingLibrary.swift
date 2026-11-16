import Foundation

/// Which controller profiles run: the bundled ones, or with an imported mapping applied (#24, #94). The app keeps the
/// imported file; this decides what it means. A rejected import or a stale saved file changes nothing.
public struct MappingLibrary: Equatable, Sendable {
    public let bundled: [ControllerProfile]
    public private(set) var profiles: [ControllerProfile]
    /// What Settings' Mapping section says is running.
    public private(set) var inUse: String
    /// Why a saved import was set aside at launch, if it was.
    public private(set) var launchProblems: [String] = []
    /// What Settings says after the last good import.
    public private(set) var importNote: String?

    static let bundledLine = "Bundled default"

    /// At launch: the bundled profiles, with `saved` (the kept import) applied if it still passes the check.
    public init(bundled: [ControllerProfile], saved: Data?) {
        self.bundled = bundled
        profiles = bundled
        inUse = Self.bundledLine
        guard let saved else { return }
        if case let .failure(problems) = apply(saved) { launchProblems = problems }
    }

    /// Applies an imported file and returns its problems. On any problem nothing changes.
    public mutating func importFile(_ data: Data, named name: String) -> [String] {
        switch apply(data) {
        case .failure(let problems):
            return problems
        case .success:
            importNote = ControllerProfile.importNote(file: name, settingsOwned: ControllerProfile.settingsOwnedKeys(in: data))
            return []
        }
    }

    /// Back to the bundled profiles.
    public mutating func reset() {
        profiles = bundled
        inUse = Self.bundledLine
        importNote = nil
    }

    private enum Outcome { case success, failure([String]) }

    private mutating func apply(_ data: Data) -> Outcome {
        guard let active = profiles.first else { return .failure(["There is no controller profile to change."]) }
        let imported: ControllerProfile
        do {
            imported = try ControllerProfile.importing(data, bundled: bundled, active: active.id)
        } catch MappingError.invalid(let problems) {
            return .failure(problems)
        } catch {
            return .failure(["\(error)"])
        }
        profiles = bundled.map { $0.id == imported.id ? imported : $0 }
        inUse = "Imported: \(imported.name)"
        return .success
    }
}
