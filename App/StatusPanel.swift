// The menu-bar panel, in the Syndicate-style theme (#34).
import ControllerBridgeCore
import ControllerBridgePresentation
import SwiftUI

extension BridgeStatus {
    /// The first controller, as the Coordinator reports it (#20, #43).
    var controller: ControllerStatus? { bridges.first }

    /// MIDI sources no controller profile matches (#43).
    var unmatchedDevices: [DeviceStatus] { devices.filter { $0.profile == nil } }

    var shownDeck: Int { controller?.deck ?? deck }

    /// Unmatched devices: a quiet gray list, or one orange NO PROFILE row when no controller is connected (#43).
    var otherDevices: OtherDevices {
        OtherDevices(unmatched: unmatchedDevices.map(\.name), controllerConnected: controller?.connected == true)
    }

    /// The status in Syndicate's words.
    var presentation: StatusPresentation { StatusPresentation(bridgeState) }

    /// Why the LEDs are dark, if they might be (#27).
    var help: HelpMessage? { HelpMessage(bridgeState) }

    /// The setup guide, naming the connected controller's profile when there is one.
    var setupGuide: SetupGuide {
        let port = switch feedback {
        case .listening(let port), .portInUse(let port): port
        case .starting, .failed: 9096
        }
        return SetupGuide(controller: controller?.profile, oscPort: 9090, feedbackPort: port)
    }

    var bridgeState: BridgeState {
        let controller: BridgeState.Controller =
            if let bridge = self.controller, bridge.connected { .connected(profile: bridge.profile ?? "Controller") } else { .notConnected }
        let feedback: BridgeState.Feedback = switch self.feedback {
        case .starting: .starting
        // The listener is up; whether Syndicate is answering is the Coordinator's call (#21).
        case .listening(let port):
            switch syndicateFeedback {
            case .waiting: .waiting(port: port)
            case .live: .live(port: port)
            case .stale: .stopped(port: port)
            }
        case .portInUse(let port): .portInUse(port: port)
        case .failed: .failed
        }
        return BridgeState(
            controller: controller, feedback: feedback, deck: shownDeck, stopped: problem != nil, lastDropout: lastDropout,
            master: self.controller?.master == true
        )
    }
}

enum AppInfo {
    /// Placeholder until the display name is picked (#29). Every window reads it from here.
    static let displayName = "Controller Bridge"
}

struct StatusPanel: View {
    let status: BridgeStatus
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let presentation = status.presentation
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.m) {
                    DeckBadgeView(deck: status.shownDeck)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppInfo.displayName).font(Theme.ui(Theme.Size.title, .bold)).foregroundStyle(Theme.text)
                        Text(subtitle).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    ForEach(presentation.lights, id: \.label) { StatusLightView(light: $0) }
                    if let master = presentation.master { StatusLightView(light: master) }
                    Spacer(minLength: 0)
                }
                let others = status.otherDevices
                if let highlighted = others.highlighted {
                    StatusLightView(light: highlighted)
                        .help(status.unmatchedDevices.first { $0.name == highlighted.label }?.note ?? "")
                }
                if let summary = others.summary {
                    OtherDevicesList(summary: summary, rows: others.rows)
                }
                HStack(spacing: Theme.Space.xl) {
                    CaptionValue(caption: "Deck", value: "\(status.shownDeck)")
                    CaptionValue(caption: "OSC", value: "9090")
                    CaptionValue(caption: "Feedback", value: feedbackPort)
                    Spacer(minLength: 0)
                }
                if let dropout = presentation.lastDropout {
                    Text(dropout).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption).lineLimit(1)
                }
                if let problem = status.problem {
                    Text(problem).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let help = status.help {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("WHY NO LEDS?").font(Theme.captionFont).foregroundStyle(Theme.caption)
                        Text(help.text).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Always there, so the guide can be reopened; the help above says when it's the fix.
                guideLink
                HStack(spacing: Theme.Space.s) {
                    SettingsLink { Text("Settings…") }.buttonStyle(FlatButtonStyle())
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(FlatButtonStyle())
                        .keyboardShortcut("q")
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.panel)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            StatusLineView(presentation: presentation, deck: status.shownDeck)
        }
        .frame(width: 360)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    /// Reopens the first-run guide (#27).
    private var guideLink: some View {
        Button("Setup guide…") { SetupGuideWindow.open(openWindow) }
            .buttonStyle(.plain)
            .font(Theme.ui(Theme.Size.body, .semibold))
            .foregroundStyle(Theme.text)
            .underline()
    }

    /// The connected controller's profile, else its last disconnect or reconnect, else none.
    private var subtitle: String {
        if let bridge = status.controller {
            if bridge.connected, let profile = bridge.profile { return profile }
            if let event = bridge.lastEvent { return event }
        }
        return "No controller"
    }

    private var feedbackPort: String {
        switch status.feedback {
        case .listening(let port), .portInUse(let port): "\(port)"
        case .starting, .failed: "–"
        }
    }
}

/// The menu-bar icon: a generic template glyph that follows the menu bar's appearance, plus a small state mark that
/// is a shape, not a color (template images can't carry color). The words are in the accessibility label.
enum MenuBarIcon {
    static func image(_ state: IconState) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let symbol = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
            symbol.draw(in: NSRect(x: 0, y: (rect.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            let dot = NSRect(x: rect.width - 6, y: 0, width: 6, height: 6)
            switch state {
            case .ok: break
            case .attention: NSBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75)).stroke()
            case .error: NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func accessibilityLabel(_ presentation: StatusPresentation) -> String {
        presentation.lights.map { "\($0.label) \($0.word)" }.joined(separator: ", ")
    }
}

/// The quiet gray list of MIDI devices no profile matches: one muted line that expands to the names.
struct OtherDevicesList: View {
    let summary: String
    let rows: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                    Text(summary).font(Theme.captionFont)
                }
                .foregroundStyle(Theme.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(summary), \(expanded ? "expanded" : "collapsed")")
            if expanded {
                ForEach(rows, id: \.self) { row in
                    Text(row).font(Theme.ui(11)).foregroundStyle(Theme.caption).padding(.leading, 12)
                }
            }
        }
    }
}
