// The Diagnostics window (#26, redesigned in #70): MIDI monitor, LED sweep and OSC log, replacing the Python `monitor`
// and `led-sweep` commands. The lines come from ControllerBridgeCore and the lists, empty states and sweep rule from
// ControllerBridgePresentation (both tested); this is only the window, in the #34 theme.
import ControllerBridgeCore
import ControllerBridgePresentation
import Observation
import SwiftUI

/// What the Diagnostics window shows. Main-actor; the engine's sink hops here once per event, only while it is open.
@MainActor @Observable
final class DiagnosticsLog {
    private(set) var lines = DiagnosticsLines()

    var hideProgressAndTime: Bool {
        get { lines.hideProgressAndTime }
        set { lines.hideProgressAndTime = newValue }
    }

    func append(_ event: DiagnosticEvent) {
        let parts = event.lineParts
        let tab: DiagnosticsTab = switch event {
        case .midiIn: .monitor
        case .oscOut, .oscIn: .osc
        case .sweep: .sweep
        }
        lines.append(to: tab, message: parts.message, label: parts.label, isUnmapped: parts.isUnmapped)
    }

    func shown(_ tab: DiagnosticsTab) -> [DiagnosticsLines.Line] { lines.shown(tab) }

    /// Clears the tab you're on; the other lists stay.
    func clear(_ tab: DiagnosticsTab) { lines.clear(tab) }
}

struct DiagnosticsWindow: View {
    typealias Tab = DiagnosticsTab

    let log: DiagnosticsLog
    let status: BridgeStatus
    let sweeping: Bool
    /// The window opened (true) or closed (false).
    let setOpen: (Bool) -> Void
    let startSweep: (Double) -> Void
    let stopSweep: () -> Void
    @State var tab = Tab.monitor
    /// Off only for snapshots: ImageRenderer draws no ScrollView content.
    var scrolls = true
    @State private var sweepDelay = 0.6

    var body: some View {
        let presentation = status.presentation
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header(presentation)
                tabBar
                content
            }
            .padding(Theme.Space.xl)
            StatusLineView(presentation: presentation)
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Color(Palette.live))
        // Only while this window is open does the bridge build anything for it.
        .onAppear { setOpen(true) }
        .onDisappear { setOpen(false) }
    }

    // MARK: Header and tabs

    /// Which controller and deck the window is watching, with the panel's lights.
    private func header(_ presentation: StatusPresentation) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            DeckBadgeView(deck: status.shownDeck)
            Text(status.controller?.profile ?? "No controller")
                .font(Theme.ui(Theme.Size.title, .semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: Theme.Space.m)
            ForEach(presentation.lights, id: \.label) { StatusLightView(light: $0) }
        }
    }

    /// The three tabs as one segmented strip on the left, and a quieter Clear log on the right for the visible tab.
    private var tabBar: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: 0) {
                ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(FlatButtonStyle(selected: tab == item))
                        .frame(width: 140)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
            Spacer(minLength: 0)
            Button("Clear log") { log.clear(tab) }
                .buttonStyle(LinkButtonStyle())
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityLabel("Clear the \(tab.rawValue)")
        }
    }

    // MARK: Tabs

    @ViewBuilder private var content: some View {
        let lines = log.shown(tab)
        let connected = status.controller?.connected == true
        switch tab {
        case .monitor:
            explain("Every MIDI message from the controller, with its mapping name or UNMAPPED.")
            columnHeader
            LineList(lines: lines, empty: tab.emptyText(controllerConnected: connected), scrolls: scrolls)
        case .sweep:
            let availability = SweepAvailability(outputOpen: status.controller?.outputOpen == true)
            HStack(spacing: Theme.Space.m) {
                Button(sweeping ? "Stop sweep" : "Start sweep") {
                    sweeping ? stopSweep() : startSweep(sweepDelay)
                }
                .buttonStyle(FlatButtonStyle())
                .frame(width: 160)
                .disabled(!sweeping && !availability.enabled)
                // FlatButtonStyle has no disabled look yet (#67), so show it here.
                .opacity(!sweeping && !availability.enabled ? 0.4 : 1)
                Stepper(value: $sweepDelay, in: 0.2...2.0, step: 0.1) {
                    Text("Step \(sweepDelay, specifier: "%.1f") s").font(Theme.data(Theme.Size.label)).foregroundStyle(Theme.text)
                }
                .disabled(sweeping)
                Spacer(minLength: 0)
            }
            if let reason = availability.reason, !sweeping { explain(reason) }
            explain("Pads and ring through all 64 colors, then every other note at full, dim and off.")
            LineList(lines: lines, empty: tab.emptyText(controllerConnected: connected), scrolls: scrolls)
        case .osc:
            Toggle(isOn: Bindable(log).hideProgressAndTime) {
                Text("Hide Progress and Time messages").font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.text)
            }
            .toggleStyle(.checkbox)
            LineList(lines: lines, empty: tab.emptyText(controllerConnected: connected), scrolls: scrolls)
        }
    }

    /// Lines up with the monitor's monospaced columns.
    private var columnHeader: some View {
        // Time ends at column 12, the message starts at 19 and the mapping at 70, as in the Python monitor's format.
        Text("        TIME  CH   MESSAGE" + String(repeating: " ", count: 44) + "MAPPING")
            .font(Theme.data(Theme.Size.label))
            .foregroundStyle(Theme.caption)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.m)
            .accessibilityHidden(true)
    }

    /// Explanatory sentences: body text in sentence case, not captions.
    private func explain(_ text: String) -> some View {
        Text(text).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
    }
}

/// Lines in the data font, newest at the bottom, with hairlines between rows. An empty list says what to do.
private struct LineList: View {
    let lines: [DiagnosticsLines.Line]
    let empty: String
    var scrolls = true

    var body: some View {
        Group {
            if lines.isEmpty {
                Text(empty)
                    .font(Theme.ui(Theme.Size.label))
                    .foregroundStyle(Theme.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { rows(lazy: true) }
                        .onChange(of: lines.last?.id) { _, last in
                            if let last { proxy.scrollTo(last, anchor: .bottom) }
                        }
                }
            } else {
                rows(lazy: false).frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }

    @ViewBuilder private func rows(lazy: Bool) -> some View {
        let content = ForEach(lines) { line in
            row(line)
                .font(Theme.data(Theme.Size.label))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.xs)
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                .id(line.id)
        }
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, Theme.Space.m)
        } else {
            VStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, Theme.Space.m)
        }
    }

    /// The line's words are exactly the Python line. UNMAPPED also gets a dot and the attention color, never color alone.
    private func row(_ line: DiagnosticsLines.Line) -> Text {
        let message = Text(line.message).foregroundStyle(Theme.text)
        guard line.isUnmapped else { return message + Text(line.label).foregroundStyle(Theme.text) }
        return message + Text("● ").foregroundStyle(Theme.attention) + Text(line.label).foregroundStyle(Theme.attention)
    }
}
