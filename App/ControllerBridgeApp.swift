import ControllerBridgeCore
import SwiftUI

@main
enum Entry {
    static func main() {
        Theme.registerFonts()
        #if DEBUG
        // Debug builds only: renders the panel to PNGs for PR screenshots and exits (#34). Not in Release.
        if let index = CommandLine.arguments.firstIndex(of: "--render-snapshots"), index + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshots.render(to: CommandLine.arguments[index + 1]) }
            exit(0)
        }
        #endif
        ControllerBridgeApp.main()
    }
}

struct ControllerBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BridgeModel()

    var body: some Scene {
        // Window style, not .menu, so it carries the dark panel.
        MenuBarExtra {
            StatusPanel(status: model.status, setDemo: model.setDemo, setDeck: { model.setDeck($0, controller: $1) })
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.window)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsWindow(
                log: model.diagnostics, status: model.status, sweeping: model.status.sweeping, setOpen: model.setDiagnostics(open:),
                startSweep: model.startLEDSweep(delay:), stopSweep: model.stopLEDSweep
            )
        }
        .defaultSize(width: 720, height: 480)
        // Opens only from the panel's Diagnostics…, never by itself at launch.
        .defaultLaunchBehavior(.suppressed)

        // The first-run guide (#27): opens itself on first launch, and from the panel's "Setup guide…".
        Window("Set up Syndicate", id: SetupGuideWindow.id) {
            SetupGuideView(guide: model.status.setupGuide)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// The menu-bar icon. It exists from launch, so it also opens the setup guide the first time (#27).
struct MenuBarLabel: View {
    let status: BridgeStatus
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let presentation = status.presentation
        Image(nsImage: MenuBarIcon.image(presentation.icon))
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(presentation))
            .task { SetupGuideWindow.openIfNew(openWindow) }
    }
}
