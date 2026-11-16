// The first-run guide (#27): what to set in Syndicate, step by step, in the Syndicate-style theme.
import ControllerBridgePresentation
import SwiftUI

struct SetupGuideView: View {
    let guide: SetupGuide
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Set up Syndicate").textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
                Text("Four settings, once").font(Theme.ui(Theme.Size.heading, .bold)).foregroundStyle(Theme.text)
                Text("\(AppInfo.displayName) talks to Syndicate over OSC. Open Syndicate's Settings and check these.")
                    .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Text("\(index + 1)")
                            .font(Theme.data(Theme.Size.value, .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 26, height: 26)
                            .background(Theme.buttonRaised, in: RoundedRectangle(cornerRadius: Theme.corner))
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(step.title).textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
                            Text(step.detail).font(Theme.ui(Theme.Size.emphasis)).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
            Text("When the bridge starts, it asks Syndicate to RESEND STATE, so the LEDs light at once.")
                .font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismissWindow(id: SetupGuideWindow.id) }
                    .buttonStyle(FlatButtonStyle())
                    .frame(width: 120)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 460)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

enum SetupGuideWindow {
    static let id = "setup-guide"
    private static let seenKey = "setupGuideSeenVersion"

    /// Opens the guide on first launch, or when its steps changed since this Mac last saw it.
    @MainActor
    static func openIfNew(_ openWindow: OpenWindowAction) {
        let defaults = UserDefaults.standard
        let seen = defaults.object(forKey: seenKey) as? Int
        guard SetupGuide.shouldShowAtLaunch(seenVersion: seen) else { return }
        defaults.set(SetupGuide.version, forKey: seenKey)
        open(openWindow)
    }

    /// An accessory (menu-bar) app must activate first, or the window opens behind the frontmost app.
    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        NSApplication.shared.activate()
        openWindow(id: id)
    }
}
