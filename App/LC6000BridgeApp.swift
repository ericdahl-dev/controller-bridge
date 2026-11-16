import LC6000Core
import SwiftUI

@main
struct LC6000BridgeApp: App {
    @State private var model = BridgeModel()

    var body: some Scene {
        // Window style, not .menu, so #34's dark panel drops in.
        MenuBarExtra {
            StatusPanel(status: model.status)
        } label: {
            // SF Symbols render as template images, so the icon follows the menu bar's appearance.
            Image(systemName: model.status.isConnected ? "slider.vertical.3" : "exclamationmark.triangle")
                .accessibilityLabel(model.status.isConnected ? "Bridge connected" : "Bridge not connected")
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings arrive in #19.")
                .padding(40)
                .preferredColorScheme(.dark)
        }
    }
}

/// The minimal panel: status, Settings… and Quit. #34 replaces its look.
struct StatusPanel: View {
    let status: BridgeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A dot plus a word: status is never shown by color alone.
            Label(status.isConnected ? "Connected" : "Not connected", systemImage: "circle.fill")
                .foregroundStyle(status.isConnected ? .green : .secondary)
                .font(.headline)
            Text(controllerLine).font(.caption)
            Text(feedbackLine).font(.caption)
            if let problem = status.problem { Text(problem).font(.caption).foregroundStyle(.red) }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .preferredColorScheme(.dark)
    }

    private var controllerLine: String {
        status.controllers.isEmpty ? "Controller: none" : "Controller: " + status.controllers.joined(separator: ", ")
    }

    private var feedbackLine: String {
        switch status.feedback {
        case .starting: "Feedback: starting"
        case .listening(let port): "Feedback: listening on port \(port)"
        case .portInUse(let port): "Feedback: port \(port) is in use by another app"
        case .failed(let reason): "Feedback: \(reason)"
        }
    }
}
