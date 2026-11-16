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
        return SetupGuide(controller: controller?.profile, oscPort: oscPort, feedbackPort: port)
    }

    var bridgeState: BridgeState {
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
        let entries = bridges.map { BridgeState.ControllerEntry(controller: Self.controllerState($0), deck: $0.deck, lastEvent: $0.lastEvent) }
        let first = entries.first
        return BridgeState(
            controller: first?.controller ?? .notConnected, feedback: feedback, deck: first?.deck ?? deck,
            stopped: problem != nil, lastDropout: lastDropoutTime, master: self.controller?.master == true, demo: demo,
            lastEvent: first?.lastEvent, others: Array(entries.dropFirst())
        )
    }

    /// Connected; or unplugged, if it was connected earlier this session (it has a last event); or never connected.
    static func controllerState(_ bridge: ControllerStatus) -> BridgeState.Controller {
        if bridge.connected { return .connected(profile: bridge.profile ?? "Controller") }
        return bridge.lastEvent != nil ? .unplugged(profile: bridge.profile) : .notConnected
    }
}

enum AppInfo {
    /// Placeholder until the display name is picked (#29). Every window reads it from here.
    static let displayName = "Controller Bridge"
}

struct StatusPanel: View {
    let status: BridgeStatus
    /// Turns the demo controller (#64) on or off.
    var setDemo: (Bool) -> Void = { _ in }
    /// The deck picker (#66): a deck for the controller at an index.
    var setDeck: (_ deck: Int, _ controller: Int) -> Void = { _, _ in }
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingQuit = false

    var body: some View {
        let presentation = status.presentation
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                // One block per controller: its name, its last event and its deck picker (#66, #25).
                ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { index, block in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    ControllerBlockView(
                        block: block, showsLight: presentation.blocks.count > 1, picks: status.problem == nil,
                        setDeck: { setDeck($0, index) }
                    )
                }
                // Two or three lights sit on one row; more (BRIDGE STOPPED, DEMO, MASTER) fold into a second.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.xl, alignment: .topLeading)],
                          alignment: .leading, spacing: Theme.Space.m) {
                    // With several controllers, each block shows its own CONTROLLER light; the row keeps the rest.
                    ForEach(presentation.lights.filter { presentation.blocks.count == 1 || $0.label != "CONTROLLER" }, id: \.label) {
                        StatusLightView(light: $0)
                    }
                    if let master = presentation.master { StatusLightView(light: master) }
                }
                let others = status.otherDevices
                if let highlighted = others.highlighted {
                    StatusLightView(light: highlighted)
                        .help(status.unmatchedDevices.first { $0.name == highlighted.label }?.note ?? "")
                }
                if let summary = others.summary {
                    OtherDevicesList(summary: summary, rows: others.rows)
                }
                // The ports, in one quiet line; the deck is in the picker (#66).
                Text("OSC → \(String(status.oscPort)) · FEEDBACK ← \(feedbackPort)")
                    .font(Theme.captionFont).foregroundStyle(Theme.caption)
                if let dropout = presentation.lastDropout {
                    CaptionValue(caption: dropout.caption, value: dropout.value)
                }
                if let help = status.help {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("WHY NO LEDS?").font(Theme.captionFont).foregroundStyle(Theme.caption)
                        Text(help.text).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if help.showsGuide {
                            Button("Setup guide") { SetupGuideWindow.open(openWindow) }.buttonStyle(FlatButtonStyle())
                        }
                        // The raw error is for a bug report, not the panel body (#66).
                        if let problem = status.problem {
                            Button("Copy details") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(problem, forType: .string)
                            }
                            .buttonStyle(LinkButtonStyle())
                        }
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    SettingsLink { Text("Settings…") }.buttonStyle(FlatButtonStyle())
                    Button("Diagnostics…") {
                        // A menu-bar (LSUIElement) app must come forward first, or the window opens behind.
                        NSApp.activate()
                        openWindow(id: "diagnostics")
                    }
                    .buttonStyle(FlatButtonStyle())
                }
                // Quiet controls: the guide, the demo, and Quit kept apart from the main buttons (#66).
                HStack(spacing: Theme.Space.l) {
                    quietButton("Setup guide") { SetupGuideWindow.open(openWindow) }
                    quietButton("Demo controller: \(status.demo ? "On" : "Off")", color: status.demo ? Theme.attention : nil) {
                        setDemo(!status.demo)
                    }
                    Spacer(minLength: 0)
                    quietButton("Quit") {
                        if presentation.quitAsks { confirmingQuit = true } else { NSApplication.shared.terminate(nil) }
                    }
                    .keyboardShortcut("q")
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.panel)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            StatusLineView(presentation: presentation)
        }
        .frame(width: 360)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .confirmationDialog("Quit? The controller stops sending to Syndicate.", isPresented: $confirmingQuit) {
            Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A quiet text button with no fill or underline, and agent2's focus ring and hover (#67). A color, when given,
    /// goes on the label itself so the style's caption gray doesn't cover it.
    @ViewBuilder
    private func quietButton(_ title: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        if let color {
            Button(action: action) { Text(title).foregroundStyle(color) }.buttonStyle(LinkButtonStyle())
        } else {
            Button(title, action: action).buttonStyle(LinkButtonStyle())
        }
    }

    private var feedbackPort: String {
        switch status.feedback {
        case .listening(let port), .portInUse(let port): "\(port)"
        case .starting, .failed: "–"
        }
    }
}

/// One controller's block: its name, its last event, its light (after the first) and its deck picker.
struct ControllerBlockView: View {
    let block: ControllerBlock
    let showsLight: Bool
    /// Off while the bridge is stopped: there is nothing to switch.
    let picks: Bool
    let setDeck: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.header.title).font(Theme.ui(Theme.Size.title, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    if let subtitle = block.header.subtitle {
                        Text(subtitle).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if showsLight { StatusLightView(light: block.light) }
            }
            if picks { DeckPicker(deck: block.deck, setDeck: setDeck) }
        }
    }
}

/// The four Syndicate decks as badges (#66): the current one in its deck color, the others quiet. A click switches.
struct DeckPicker: View {
    let deck: Int
    let setDeck: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(1...4, id: \.self) { number in
                Button { setDeck(number) } label: {
                    if number == deck {
                        // Not color alone: the current deck also gets the selected bar under it (#67).
                        DeckBadgeView(deck: number)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color(Palette.selectedBar)).frame(height: 2).offset(y: 4)
                            }
                    } else {
                        Text("\(number)")
                            .font(Theme.data(15, .semibold))
                            .foregroundStyle(Theme.caption)
                            .frame(width: 26, height: 26)
                            .background(Theme.button, in: RoundedRectangle(cornerRadius: Theme.corner))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Deck \(number)")
                .accessibilityAddTraits(number == deck ? .isSelected : [])
            }
        }
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
            .buttonStyle(LinkButtonStyle())
            .accessibilityLabel("\(summary), \(expanded ? "expanded" : "collapsed")")
            if expanded {
                ForEach(rows, id: \.self) { row in
                    Text(row).font(Theme.ui(11)).foregroundStyle(Theme.caption).padding(.leading, 12)
                }
            }
        }
    }
}
