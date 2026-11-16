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
        // One unit following its layers shows as one controller, on its active layer's deck (#79).
        let folded = CoordinatorStatus(controllers: bridges).collapsingLayers().controllers
        let entries = folded.map {
            BridgeState.ControllerEntry(controller: Self.controllerState($0), deck: $0.deck, lastEvent: $0.lastEvent,
                                        followsLayers: $0.followsLayers)
        }
        let first = entries.first
        return BridgeState(
            controller: first?.controller ?? .notConnected, feedback: feedback, deck: first?.deck ?? deck,
            stopped: problem != nil, lastDropout: lastDropoutTime, master: self.controller?.master == true, demo: demo,
            lastEvent: first?.lastEvent, others: Array(entries.dropFirst()), stopReason: stopReason,
            followsLayers: first?.followsLayers ?? false
        )
    }

    /// The panel's controller state, by the tested mapping in Presentation (#91).
    static func controllerState(_ bridge: ControllerStatus) -> BridgeState.Controller {
        BridgeState.Controller(
            connected: bridge.connected, profile: bridge.profile, lastProfile: bridge.lastProfile,
            lastDisconnect: bridge.lastDisconnect.map(Self.disconnect)
        )
    }

    /// Core's reason, one to one.
    static func disconnect(_ reason: DisconnectReason) -> BridgeState.Disconnect {
        switch reason {
        case .unplugged: .unplugged
        case .sendFailed: .sendFailed
        case .inputFailed: .inputFailed
        case .deviceChanged: .deviceChanged
        case .removed: .removed
        case .stopped: .stopped
        }
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
    /// Quit asks inside the panel while feedback is live (#131): a dialog on a menu-bar window may never show.
    @State var quitFlow = QuitFlow()

    var body: some View {
        let presentation = status.presentation
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                // One block per controller: its name, its last event and its deck picker (#66, #25).
                ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { index, block in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    ControllerBlockView(
                        block: block, showsLight: presentation.blocks.count > 1, picker: presentation.deckPicker,
                        deckProblem: status.deckProblem,
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
                        Text("Why no LEDs?").textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
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
                            .buttonStyle(CaptionButtonStyle()).font(Theme.captionFont).foregroundStyle(Theme.caption)
                        }
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    SettingsLink { Text("Settings…") }.buttonStyle(FlatButtonStyle()).keyboardShortcut(",")
                    Button("Diagnostics…") {
                        // A menu-bar (LSUIElement) app must come forward first, or the window opens behind.
                        NSApp.activate()
                        openWindow(id: "diagnostics")
                    }
                    .buttonStyle(FlatButtonStyle())
                    .keyboardShortcut("d")
                }
                // Quiet controls: the guide, the demo, and Quit kept apart from the main buttons (#66).
                if quitFlow.confirming {
                    // The question in the panel itself: Return quits, Esc cancels (#131).
                    HStack(spacing: Theme.Space.m) {
                        Text(QuitFlow.question).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Cancel") { quitFlow.cancel() }
                            .buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction).frame(width: 90)
                        Button("Quit") { if quitFlow.confirm() == .quitNow { NSApplication.shared.terminate(nil) } }
                            .buttonStyle(FlatButtonStyle()).keyboardShortcut(.defaultAction).frame(width: 90)
                    }
                } else {
                HStack(spacing: Theme.Space.l) {
                    quietButton("Setup guide") { SetupGuideWindow.open(openWindow) }
                    // Not while stopped: there's no pipe to switch the demo on with (#88).
                    if presentation.showsDemoToggle {
                        quietButton("Demo controller: \(status.demo ? "On" : "Off")", color: status.demo ? Theme.attention : Theme.caption) {
                            setDemo(!status.demo)
                        }
                    }
                    Spacer(minLength: 0)
                    quietButton("Quit") {
                        if quitFlow.pressQuit(asks: presentation.quitAsks) == .quitNow { NSApplication.shared.terminate(nil) }
                    }
                }
                }
            }
            .padding(Theme.Space.l)
            .background(Theme.panel)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            StatusLineView(presentation: presentation)
        }
        .frame(width: 360)
        .background(Theme.background)
        // ⌘Q quits without asking: a DJ pressing it means it (#131).
        .background {
            Button("Quit now") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q").opacity(0).accessibilityHidden(true)
        }
        .onDisappear { quitFlow.panelClosed() }
    }

    /// A small caption-style text button, with no fill and no underline.
    private func quietButton(_ title: String, color: Color = Theme.caption, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(CaptionButtonStyle())
            .font(Theme.captionFont)
            .foregroundStyle(color)
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
    /// Usable, off with a reason (demo mode), or hidden (stopped), from the tested presentation (#90).
    let picker: DeckPickerState
    /// A refused deck change, shown under the picker (#90).
    let deckProblem: String?
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
            if let note = block.deckNote {
                // The controller's own layers pick the deck (#79): show it, with no picker to fight it.
                HStack(spacing: Theme.Space.s) {
                    DeckBadgeView(deck: block.deck)
                    Text(note).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
                }
                .accessibilityElement(children: .combine)
            } else if picker != .hidden {
                DeckPicker(deck: block.deck, state: picker, problem: deckProblem, setDeck: setDeck)
            }
        }
        // One container per controller, named with its number, so VoiceOver can tell two blocks apart (#89).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(block.accessibilityLabel)
    }
}

/// The four Syndicate decks as badges (#66): the current one in its deck color, the others quiet. A click switches.
struct DeckPicker: View {
    let deck: Int
    var state: DeckPickerState = .enabled
    var problem: String?
    let setDeck: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            badges
                .disabled(state != .enabled)
                .opacity(state == .enabled ? 1 : 0.4)
            if case .disabled(let reason) = state {
                Text(reason).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
            }
            if let problem {
                Text(problem).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.error).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var badges: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(1...4, id: \.self) { number in
                Button { setDeck(number) } label: {
                    if number == deck {
                        DeckBadgeView(deck: number)
                    } else {
                        Text("\(number)")
                            .font(Theme.data(15, .semibold))
                            .foregroundStyle(Theme.caption)
                            .frame(width: 26, height: 26)
                            .background(Theme.button, in: RoundedRectangle(cornerRadius: Theme.corner))
                    }
                }
                .buttonStyle(CaptionButtonStyle())
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
                    Text(summary).textCase(.uppercase).font(Theme.captionFont)
                }
                .foregroundStyle(Theme.caption)
            }
            .buttonStyle(CaptionButtonStyle())
            .accessibilityLabel("\(summary), \(expanded ? "expanded" : "collapsed")")
            if expanded {
                ForEach(rows, id: \.self) { row in
                    Text(row).font(Theme.ui(11)).foregroundStyle(Theme.caption).padding(.leading, 12)
                }
            }
        }
    }
}
