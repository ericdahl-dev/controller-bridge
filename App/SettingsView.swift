// The Settings window (#19), in the Syndicate theme (#34). Not unit-tested: the settings model is tested in
// ControllerBridgeKit; this view only edits a draft and hands it to BridgeModel.apply.
import AppKit
import ControllerBridgeCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: BridgeModel

    @State private var draft: BridgeSettings?
    @State private var sources: [MIDIEndpoint] = []
    @State private var destinations: [MIDIEndpoint] = []
    @State private var problems: [String] = []
    @State private var saved = false
    @State private var startAtLogin = LoginItem.isEnabled
    @State private var loginProblem: String?
    @State private var mappingProblems: [String] = []
    @State private var mappingNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let binding = Binding($draft) {
                form(binding)
            } else {
                Text("The bridge didn't start, so there is nothing to set.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.caption)
            }
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func form(_ settings: Binding<BridgeSettings>) -> some View {
        ForEach(settings.controllers.indices, id: \.self) { index in
            controllerSection(settings, index)
        }
        HStack {
            if settings.wrappedValue.controllers.count < 4 {
                Button("Add controller") { settings.wrappedValue.controllers.append(Self.newEntry(after: settings.wrappedValue.controllers)) }
                    .buttonStyle(FlatButtonStyle())
            }
        }
        Toggle("LEDs", isOn: settings.ledsEnabled).font(Theme.ui(12))
        ForEach(settings.wrappedValue.warnings, id: \.self) { note($0, color: Theme.attention) }

        section("OSC") {
            field("Host", text: settings.syndicateHost)
            field("Port", value: settings.syndicatePort)
        }

        section("Feedback") {
            field("Port", value: settings.feedbackPort)
            Picker("Listen on", selection: settings.feedbackListen) {
                Text("This Mac only").tag(FeedbackListen.thisMac)
                Text("All networks").tag(FeedbackListen.allNetworks)
            }
            .font(Theme.ui(12))
            if settings.wrappedValue.feedbackListen == .allNetworks {
                note("For Syndicate on another Mac. macOS asks once for permission to use the local network; allow it, or no feedback arrives.")
            }
        }

        section("Mapping") {
            note(model.status.mappingInUse)
            HStack(spacing: Theme.Space.s) {
                Button("Import…") { importMapping() }.buttonStyle(FlatButtonStyle())
                Button("Export…") { exportMapping() }.buttonStyle(FlatButtonStyle())
                Button("Reset to default") { model.resetMapping(); mappingProblems = []; mappingNote = "Back to the bundled mapping." }
                    .buttonStyle(FlatButtonStyle())
            }
            if let mappingNote { note(mappingNote) }
            ForEach(mappingProblems, id: \.self) { note($0, color: Theme.error) }
        }

        section("Start") {
            Toggle("Start at login", isOn: $startAtLogin)
                .font(Theme.ui(12))
                .onChange(of: startAtLogin) { _, enabled in setLogin(enabled) }
            if let loginProblem { note(loginProblem, color: Theme.error) }
        }

        ForEach(problems, id: \.self) { note($0, color: Theme.error) }
        if saved { note("Saved.") }

        HStack {
            Button("Revert") { load() }.buttonStyle(FlatButtonStyle())
            Button("Apply") { apply(settings.wrappedValue) }.buttonStyle(FlatButtonStyle())
        }
    }

    // MARK: Mapping (#24)

    private func importMapping() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a mapping file. A bad file is refused, and the current mapping keeps running."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mappingProblems = model.importMapping(from: url)
        mappingNote = mappingProblems.isEmpty ? "Imported \(url.lastPathComponent)." : "Not imported: fix these and try again."
    }

    private func exportMapping() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(model.profiles.first?.id ?? "mapping").json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportMapping(to: url)
            mappingProblems = []
            mappingNote = "Exported \(url.lastPathComponent)."
        } catch {
            mappingProblems = ["Couldn't export: \(error.localizedDescription)"]
        }
    }

    // MARK: Pieces

    /// One controller entry: its deck, devices and channel (#25).
    private func controllerSection(_ settings: Binding<BridgeSettings>, _ index: Int) -> some View {
        // Bounds-checked: right after a removal, SwiftUI can still read the removed row once.
        let controller = Binding<ControllerSettings>(
            get: { settings.wrappedValue.controllers.indices.contains(index) ? settings.wrappedValue.controllers[index] : Self.newEntry(after: []) },
            set: { if settings.wrappedValue.controllers.indices.contains(index) { settings.wrappedValue.controllers[index] = $0 } }
        )
        let title = settings.wrappedValue.controllers.count > 1 ? "Controller \(index + 1)" : "Controller"
        return section(title) {
            Picker("Deck", selection: controller.deck) {
                ForEach(1...4, id: \.self) { Text("Deck \($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            devicePicker("MIDI input", selection: controller.input, devices: sources)
            devicePicker("MIDI output", selection: controller.output, devices: destinations)
            Picker("Channel", selection: controller.channel) {
                Text("From the profile").tag(Int?.none)
                ForEach(1...16, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
            }
            .font(Theme.ui(12))
            if settings.wrappedValue.controllers.count > 1 {
                Button("Remove controller \(index + 1)") { settings.wrappedValue.controllers.remove(at: index) }
                    .buttonStyle(FlatButtonStyle())
            }
        }
    }

    /// A new entry on the first deck no controller drives yet, with automatic devices.
    private static func newEntry(after entries: [ControllerSettings]) -> ControllerSettings {
        let used = Set(entries.map(\.deck))
        return ControllerSettings(deck: (1...4).first { !used.contains($0) } ?? 1, input: nil, output: nil)
    }

    private func section(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption.uppercased()).font(Theme.captionFont).foregroundStyle(Theme.caption)
            content()
        }
    }

    private func devicePicker(_ label: String, selection: Binding<MIDIEndpoint?>, devices: [MIDIEndpoint]) -> some View {
        Picker(label, selection: selection) {
            Text("Automatic").tag(MIDIEndpoint?.none)
            ForEach(devices) { Text($0.name).tag(MIDIEndpoint?.some($0)) }
            // A saved device that isn't plugged in stays selectable, so the choice isn't lost.
            if let chosen = selection.wrappedValue, !devices.contains(chosen) {
                Text("\(chosen.name) (not connected)").tag(MIDIEndpoint?.some(chosen))
            }
        }
        .font(Theme.ui(12))
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(label, text: text).labelsHidden().font(Theme.data(13)).frame(width: 160)
        }
        .font(Theme.ui(12))
    }

    private func field(_ label: String, value: Binding<Int>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number.grouping(.never)).labelsHidden().font(Theme.data(13)).frame(width: 80)
        }
        .font(Theme.ui(12))
    }

    private func note(_ text: String, color: Color = Theme.caption) -> some View {
        Text(text).font(Theme.ui(11)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func load() {
        draft = model.settings
        sources = model.sources
        destinations = model.destinations
        problems = []
        saved = false
        startAtLogin = LoginItem.isEnabled
        // A menu-bar app has no Dock icon, so its windows open behind the front app unless it activates.
        NSApp.activate()
        DispatchQueue.main.async { NSApp.windows.first { $0.isVisible && $0.canBecomeKey }?.makeKeyAndOrderFront(nil) }
    }

    private func apply(_ settings: BridgeSettings) {
        do {
            try model.apply(settings)
            problems = []
            saved = true
        } catch {
            if case .invalid(let list) = error { problems = list }
            saved = false
        }
    }

    private func setLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.set(enabled)
            loginProblem = nil
        } catch {
            loginProblem = "Couldn't change start at login: \(error.localizedDescription)"
            startAtLogin = LoginItem.isEnabled
        }
    }
}
