// The Diagnostics window (#26): MIDI monitor, LED sweep and OSC log, replacing the Python `monitor` and `led-sweep`
// commands. The lines come from ControllerBridgeCore (tested there); this is only the window, in the #34 theme.
import ControllerBridgeCore
import Observation
import SwiftUI

/// What the Diagnostics window shows. Main-actor; the engine's sink hops here once per event, only while it is open.
@MainActor @Observable
final class DiagnosticsLog {
    /// Each list keeps its newest lines only, so a long set doesn't grow without bound.
    static let limit = 500

    private(set) var monitor: [Line] = []
    private(set) var osc: [Line] = []
    private(set) var sweep: [Line] = []
    /// Progress and Time feedback arrive many times a second while playing; hidden by default.
    var hideProgressAndTime = true

    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    private var nextID = 0

    func append(_ event: DiagnosticEvent) {
        nextID += 1
        let line = Line(id: nextID, text: event.text)
        switch event {
        case .midiIn: Self.push(line, to: &monitor)
        case .oscOut, .oscIn: Self.push(line, to: &osc)
        case .sweep: Self.push(line, to: &sweep)
        }
    }

    var shownOSC: [Line] {
        guard hideProgressAndTime else { return osc }
        return osc.filter { !Self.isProgressOrTime($0.text) }
    }

    func clear() {
        monitor.removeAll()
        osc.removeAll()
        sweep.removeAll()
    }

    /// "OSC <- /Syndicate/Deck/1/Progress 0.25" or ".../Time 61": the address's last part, before the arguments.
    private static func isProgressOrTime(_ text: String) -> Bool {
        guard text.hasPrefix("OSC <- ") else { return false }
        let address = text.dropFirst(7).split(separator: " ").first ?? ""
        let last = address.split(separator: "/").last?.lowercased()
        return last == "progress" || last == "time"
    }

    private static func push(_ line: Line, to list: inout [Line]) {
        list.append(line)
        if list.count > limit { list.removeFirst(list.count - limit) }
    }
}

struct DiagnosticsWindow: View {
    let log: DiagnosticsLog
    let sweeping: Bool
    /// The window opened (true) or closed (false).
    let setOpen: (Bool) -> Void
    let startSweep: (Double) -> Void
    let stopSweep: () -> Void
    @State var tab = Tab.monitor
    /// Off only for snapshots: ImageRenderer draws no ScrollView content.
    var scrolls = true
    @State private var sweepDelay = 0.6

    enum Tab: String, CaseIterable {
        case monitor = "MIDI Monitor"
        case sweep = "LED Sweep"
        case osc = "OSC Log"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(FlatButtonStyle(raised: tab == item))
                }
                Spacer(minLength: 0)
                Button("Clear") { log.clear() }.buttonStyle(FlatButtonStyle())
            }
            switch tab {
            case .monitor:
                caption("Every MIDI message from the controller, with its mapping name or UNMAPPED.")
                LineList(lines: log.monitor, scrolls: scrolls)
            case .sweep:
                HStack(spacing: 10) {
                    Button(sweeping ? "Stop sweep" : "Start sweep") {
                        sweeping ? stopSweep() : startSweep(sweepDelay)
                    }
                    .buttonStyle(FlatButtonStyle())
                    .frame(width: 160)
                    Stepper(value: $sweepDelay, in: 0.2...2.0, step: 0.1) {
                        Text("Step \(sweepDelay, specifier: "%.1f") s").font(Theme.data(12)).foregroundStyle(Theme.text)
                    }
                    .disabled(sweeping)
                    Spacer(minLength: 0)
                }
                caption("Pads and ring through all 64 colors, then every other note at full, dim and off.")
                LineList(lines: log.sweep, scrolls: scrolls)
            case .osc:
                Toggle(isOn: Bindable(log).hideProgressAndTime) {
                    Text("Hide Progress and Time").font(Theme.ui(11)).foregroundStyle(Theme.text)
                }
                .toggleStyle(.checkbox)
                LineList(lines: log.shownOSC, scrolls: scrolls)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        // Only while this window is open does the bridge build anything for it.
        .onAppear { setOpen(true) }
        .onDisappear { setOpen(false) }
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.captionFont).foregroundStyle(Theme.caption)
    }
}

/// Lines in the data font, newest at the bottom, with hairlines between rows.
private struct LineList: View {
    let lines: [DiagnosticsLog.Line]
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView { rows(lazy: true) }
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    .onChange(of: lines.last?.id) { _, last in
                        if let last { proxy.scrollTo(last, anchor: .bottom) }
                    }
            }
        } else {
            rows(lazy: false)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        }
    }

    @ViewBuilder private func rows(lazy: Bool) -> some View {
        let content = ForEach(lines) { line in
            Text(line.text)
                .font(Theme.data(12))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
                .id(line.id)
        }
        if lazy {
            LazyVStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, 8)
        }
    }
}
