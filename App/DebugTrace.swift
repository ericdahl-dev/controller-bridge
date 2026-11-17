// The debug trace (#395): Debug builds log everything an agent needs to diagnose the hardware to os_log and to a rolling
// file it can read directly. Release and TestFlight builds compile none of this. Not unit-tested: the line format, the
// sampler and the rolling file are tested in ControllerBridgeKit (TraceTests); this is the wiring.
#if DEBUG
import ControllerBridgeCore
import Foundation
import os

final class DebugTrace: @unchecked Sendable {
    static let shared = DebugTrace()

    /// The app container's Library/Logs/DeckBridge/deckbridge.log (sandboxed, so under the container).
    let fileURL: URL
    private let file: RollingLogFile
    private let queue = DispatchQueue(label: "dev.ericdahl.ControllerBridge.trace")
    private let loggers: [TraceCategory: Logger]
    /// The last status summary written, so only changes are logged.
    private var lastStatus = ""

    private init() {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DeckBridge", isDirectory: true)
        file = RollingLogFile(directory: logs, name: "deckbridge.log", cap: 20_000_000, keep: 3)
        fileURL = file.url
        loggers = Dictionary(uniqueKeysWithValues: TraceCategory.allCases.map {
            ($0, Logger(subsystem: "dev.ericdahl.ControllerBridge", category: $0.rawValue))
        })
        // Each launch starts with where the file is, so an agent reading os_log finds it too.
        let path = fileURL.path
        loggers[.coordinator]?.notice("Debug trace file: \(path, privacy: .public)")
        file.append(TraceLine.format(at: .now, .coordinator, "Debug trace started; file \(path)"))
    }

    /// Where the Kit's trace goes: os_log at once, the file on a background queue.
    var sink: TraceSink {
        { [self] category, text in
            let now = Date.now
            if category == .error { loggers[category]?.error("\(text, privacy: .public)") } else {
                loggers[category]?.debug("\(text, privacy: .public)")
            }
            queue.async { self.file.append(TraceLine.format(at: now, category, text)) }
        }
    }

    /// The Coordinator's status, logged when it changes: controllers (deck, layer, profile, connection), feedback,
    /// missing subscriptions and another host.
    func status(_ status: CoordinatorStatus) {
        let summary = "controllers \(status.controllers) feedback \(status.feedback) missing subscriptions "
            + "\(status.missingSubscriptions) other host \(status.otherHost)"
        queue.async {
            guard summary != self.lastStatus else { return }
            self.lastStatus = summary
            self.file.append(TraceLine.format(at: .now, .coordinator, summary))
            if !status.missingSubscriptions.isEmpty {
                self.file.append(TraceLine.format(at: .now, .subscriptions, "missing: \(status.missingSubscriptions)"))
            }
        }
    }
}
#endif
