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

    /// The status in Syndicate's words.
    var presentation: StatusPresentation {
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
        return StatusPresentation(BridgeState(
            controller: controller, feedback: feedback, deck: shownDeck, stopped: problem != nil, lastDropout: lastDropout
        ))
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    DeckBadgeView(deck: status.shownDeck)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppInfo.displayName).font(Theme.ui(14, .bold)).foregroundStyle(Theme.text)
                        Text(subtitle).font(Theme.ui(11)).foregroundStyle(Theme.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(presentation.lights, id: \.label) { StatusLightView(light: $0) }
                    Spacer(minLength: 0)
                }
                if !status.unmatchedDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(status.unmatchedDevices.prefix(3), id: \.name) { device in
                            StatusLightView(light: StatusLight(unmatchedDevice: device.name))
                                .help(device.note ?? "")
                        }
                    }
                }
                HStack(spacing: 16) {
                    CaptionValue(caption: "Deck", value: "\(status.shownDeck)")
                    CaptionValue(caption: "OSC", value: "9090")
                    CaptionValue(caption: "Feedback", value: feedbackPort)
                    Spacer(minLength: 0)
                }
                if let dropout = presentation.lastDropout {
                    Text(dropout).font(Theme.ui(11)).foregroundStyle(Theme.caption).lineLimit(1)
                }
                if let problem = status.problem {
                    Text(problem).font(Theme.ui(11)).foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    SettingsLink { Text("Settings…") }.buttonStyle(FlatButtonStyle())
                    Button {
                        // A menu-bar (LSUIElement) app must come forward first, or the window opens behind.
                        NSApp.activate()
                        openWindow(id: "diagnostics")
                    } label: {
                        // Three buttons share 260 pt: the longest label shrinks a little rather than wrap.
                        Text("Diagnostics…").lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .buttonStyle(FlatButtonStyle())
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(FlatButtonStyle())
                        .keyboardShortcut("q")
                }
            }
            .padding(12)
            .background(Theme.panel)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            StatusLineView(presentation: presentation, deck: status.shownDeck)
        }
        .frame(width: 320)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
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
