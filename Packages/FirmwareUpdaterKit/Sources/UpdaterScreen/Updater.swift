import DeviceFinder
import Observation

/// The app's model (#688): finds what is plugged in, and looks again when USB changes, so a newly installed driver
/// shows without a restart. Looks never overlap: one asked for during a look runs once, after it.
@MainActor @Observable
public final class Updater {
    public private(set) var screen = UpdaterScreen(found: Found(), lc6000WarningAccepted: false)
    public private(set) var looking = false
    private var lookAgain = false
    private var found = Found()
    private var lc6000WarningAccepted = false
    private let finder: DeviceFinder
    private let changes: AsyncStream<Void>

    /// `changes` yields when a USB device arrives or leaves.
    public init(finder: DeviceFinder, changes: AsyncStream<Void>) {
        self.finder = finder
        self.changes = changes
    }

    public func refresh() async {
        guard !looking else {
            lookAgain = true
            return
        }
        looking = true
        repeat {
            lookAgain = false
            found = await finder.find()
            show()
        } while lookAgain
        looking = false
    }

    /// Looks again on every USB change, until the stream ends.
    public func watch() async {
        for await _ in changes { await refresh() }
    }

    public func acceptLC6000Warning() {
        lc6000WarningAccepted = true
        show()
    }

    private func show() {
        screen = UpdaterScreen(found: found, lc6000WarningAccepted: lc6000WarningAccepted)
    }
}
