// The first-run guide (#27): what to set in Syndicate, step by step, in the Syndicate-style theme.
import ControllerBridgePresentation
import SwiftUI

struct SetupGuideView: View {
    let guide: SetupGuide
    /// The panel's status, for the live check at the bottom (#68).
    let presentation: StatusPresentation
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x4) {
            heading
            steps
            Text(SetupGuide.footer)
                .font(Theme.ui(12)).foregroundStyle(Theme.caption)
                .fixedSize(horizontal: false, vertical: true)
            OtherAppsCallout(note: guide.otherAppsNote)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            liveCheck
        }
        .padding(Theme.Step.x6)
        .frame(width: 460)
        .background(Theme.panel)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x1) {
            Text("Set up Syndicate").font(Theme.labelFont).foregroundStyle(Theme.caption)
            Text("Four settings, once").font(Theme.ui(22, .medium)).tracking(-0.8).foregroundStyle(Theme.text)
            Text("\(AppInfo.displayName) talks to Syndicate over OSC. Open Syndicate's Settings and check these.")
                .font(Theme.ui(13)).foregroundStyle(Theme.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    /// Numbered steps with hairlines between, as the site's support page (#171).
    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                StepRow(number: index + 1, step: step)
                    .padding(.vertical, Theme.Step.x3)
            }
        }
    }

    /// The live check: the panel's lights, so the DJ sees each step take (#68).
    private var liveCheck: some View {
        HStack(alignment: .center, spacing: Theme.Step.x6) {
            ForEach(presentation.lights, id: \.label) { StatusLightView(light: $0, size: 13) }
            Spacer()
            Button(SetupGuide.doneTitle(feedbackLive: feedbackLive)) { dismissWindow(id: SetupGuideWindow.id) }
                // Green once Syndicate answers: then Done finishes the job.
                .buttonStyle(PillButtonStyle(kind: feedbackLive ? .primary : .secondary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var feedbackLive: Bool {
        presentation.lights.contains { $0.kind == .feedback && $0.tone == .live }
    }
}

/// One step: a large muted numeral, Syndicate's menu path in mono, what to do, and a checklist when there is one.
private struct StepRow: View {
    let number: Int
    let step: SetupGuide.Step

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Step.x2) {
            // Plain digits, no square: squares are for decks (#68).
            Text("\(number)")
                .font(Theme.ui(20, .medium))
                .foregroundStyle(Theme.caption)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Step.x1) {
                Text(step.title).font(Theme.labelFont).foregroundStyle(Theme.caption)
                Text(step.detail).font(Theme.ui(13)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !step.checklist.isEmpty { checklist.padding(.top, Theme.Step.x1) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var checklist: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: Theme.Step.x1) {
            ForEach(step.checklist, id: \.self) { item in
                Text("☐ " + item).font(Theme.data(11.5)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Another DJ app can switch the controller's MIDI mode until it restarts (#79): an attention callout, dot and words.
private struct OtherAppsCallout: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Step.x2) {
            Circle().fill(Theme.attention).frame(width: 7, height: 7).padding(.top, 5).accessibilityHidden(true)
            Text(note).font(Theme.ui(12)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Step.x3)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.attention.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.attention.opacity(0.35), lineWidth: 1))
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
