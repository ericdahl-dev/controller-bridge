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
    @State private var model = BridgeModel()

    var body: some Scene {
        // Window style, not .menu, so it carries the dark panel.
        MenuBarExtra {
            StatusPanel(status: model.status)
        } label: {
            let presentation = model.status.presentation
            Image(nsImage: MenuBarIcon.image(presentation.icon))
                .accessibilityLabel(MenuBarIcon.accessibilityLabel(presentation))
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings arrive in #19.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.text)
                .padding(40)
                .background(Theme.background)
                .preferredColorScheme(.dark)
        }
    }
}
