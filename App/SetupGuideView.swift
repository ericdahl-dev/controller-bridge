// The first-run guide (#27): what to set in Syndicate, step by step, in the Syndicate-style theme.
import ControllerBridgePresentation
import SwiftUI

struct SetupGuideView: View {
    let guide: SetupGuide
    /// The panel's status, for the live check at the bottom (#68).
    let presentation: StatusPresentation
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
                        // Plain digits, no square: squares are for decks (#68).
                        Text("\(index + 1)")
                            .font(Theme.data(Theme.Size.value, .semibold))
                            .foregroundStyle(Theme.caption)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(step.title).textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
                            Text(step.detail).font(Theme.ui(Theme.Size.emphasis)).foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if !step.checklist.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                          alignment: .leading, spacing: Theme.Space.xs) {
                                    ForEach(step.checklist, id: \.self) { item in
                                        Text("☐ " + item).font(Theme.data(Theme.Size.body)).foregroundStyle(Theme.text)
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
            Text(SetupGuide.footer)
                .font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
                .fixedSize(horizontal: false, vertical: true)
            // Another DJ app can switch the controller's MIDI mode until it restarts (#79).
            Text(guide.otherAppsNote)
                .font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.attention)
                .fixedSize(horizontal: false, vertical: true)
            // The live check: the panel's lights, so the DJ sees each step take (#68).
            HStack(alignment: .bottom, spacing: Theme.Space.xl) {
                ForEach(presentation.lights, id: \.label) { StatusLightView(light: $0) }
                Spacer()
                Button(SetupGuide.doneTitle(feedbackLive: feedbackLive)) { dismissWindow(id: SetupGuideWindow.id) }
                    .buttonStyle(FlatButtonStyle())
                    .frame(width: feedbackLive ? 200 : 120)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 460)
        .background(Theme.background)
    }

    private var feedbackLive: Bool {
        presentation.lights.contains { $0.label == "FEEDBACK" && $0.word == "LIVE" }
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
