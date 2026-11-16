// The Settings window (#19), in the Syndicate theme (#34), after its design pass (#68). Not unit-tested: the settings
// model and its field-keyed problems are tested in ControllerBridgeKit; this view edits a draft and hands it to
// BridgeModel.apply.
import AppKit
import ControllerBridgeCore
import ControllerBridgePresentation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: BridgeModel

    @Environment(\.openWindow) private var openWindow
    @State private var draft: BridgeSettings?
    /// The settings the draft started from, to tell the DJ's edits from changes made elsewhere (#90).
    @State private var base: BridgeSettings?
    @State private var sources: [MIDIEndpoint] = []
    @State private var destinations: [MIDIEndpoint] = []
    /// Problems from the last Apply, shown under their fields; the rest (such as the bridge not running) below.
    @State private var fieldProblems: [SettingsProblem] = []
    /// The host name being looked up by Apply, while it is (#84).
    @State private var checkingHost: String?
    @State private var otherProblems: [String] = []
    @State private var saved = false
    /// What Apply said about the save, such as needing a restart (#88).
    @State private var savedNote: String?
    @State private var startAtLogin = LoginItem.isEnabled
    @State private var loginProblem: String?
    @State private var mappingProblems: [String] = []
    @State private var mappingNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let binding = Binding($draft) {
                form(binding)
            } else {
                emptyState
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 440, alignment: .leading)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        // Brings this window, not whichever window was open before, to the front (#62).
        .background(FrontWindow())
        .onAppear(perform: load)
        .onChange(of: draft) { _, _ in saved = false }
        // A deck picked in the panel while Settings is open: keep it, and keep the DJ's own edits (#90).
        .onChange(of: model.settings) { _, new in
            guard let new, let draft, let base, new != base else { return }
            self.draft = BridgeSettings.rebased(draft: draft, base: base, onto: new)
            self.base = new
        }
    }

    // MARK: Form

    @ViewBuilder
    private func form(_ settings: Binding<BridgeSettings>) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
            ForEach(settings.controllers.indices, id: \.self) { index in
                controllerRows(settings, index)
            }
            row("") {
                HStack(spacing: Theme.Space.m) {
                    if settings.wrappedValue.controllers.count < 4 {
                        Button("Add controller") {
                            settings.wrappedValue.controllers.append(Self.newEntry(after: settings.wrappedValue.controllers))
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                    Toggle("Controller LEDs", isOn: settings.ledsEnabled).font(Theme.ui(Theme.Size.label)).tint(Self.on)
                }
                ForEach(settings.wrappedValue.warnings, id: \.self) { note($0, color: Theme.attention) }
            }

            heading("Syndicate OSC input")
            row("Host") { field(text: settings.syndicateHost, width: 160, field: .host) }
            row("Port") {
                field(value: settings.syndicatePort, field: .oscPort)
                hint("Syndicate's OSC listen port")
            }

            heading("OSC feedback")
            row("Port") {
                field(value: settings.feedbackPort, field: .feedbackPort)
                hint("Syndicate's DEST IP is 127.0.0.1, PORT this number")
            }
            row("Listen on") {
                Picker("Listen on", selection: settings.feedbackListen) {
                    Text("This Mac only").tag(FeedbackListen.thisMac)
                    Text("All networks").tag(FeedbackListen.allNetworks)
                }
                .labelsHidden().fixedSize()
                if settings.wrappedValue.feedbackListen == .allNetworks {
                    hint("For Syndicate on another Mac. macOS asks once for local-network permission; allow it, or no feedback arrives.")
                }
            }
            // What to set on Syndicate's side is in the guide, reachable from here as well as the panel (#66 item 6).
            row("") {
                Button("Setup Guide…") { SetupGuideWindow.open(openWindow) }.buttonStyle(LinkButtonStyle())
            }

            decksSection(settings)

            heading("Mapping")
            row("In use") {
                note(model.status.mappingInUse)
                HStack(spacing: Theme.Space.s) {
                    Button("Import…") { importMapping() }.buttonStyle(FlatButtonStyle())
                    Button("Export…") { exportMapping() }.buttonStyle(FlatButtonStyle())
                    Button("Reset") {
                        let problem = model.resetMapping()
                        mappingProblems = problem.map { [$0] } ?? []
                        mappingNote = problem == nil ? "Back to the bundled mapping." : nil
                    }
                        .buttonStyle(FlatButtonStyle())
                        .help("Go back to the bundled mapping")
                }
                if let mappingNote { note(mappingNote) }
                ForEach(mappingProblems, id: \.self) { note($0, color: Theme.error) }
            }

            heading("Login")
            row("Appearance") {
                // Syndicate's LIGHT MODE can't be read over OSC, so pick it here to match (#127).
                Picker("Appearance", selection: settings.appearance) {
                    Text("Match macOS").tag(Appearance.matchMacOS)
                    Text("Dark").tag(Appearance.dark)
                    Text("Light").tag(Appearance.light)
                }
                .labelsHidden().fixedSize()
            }
            row("Start") {
                Toggle("Start at login", isOn: $startAtLogin)
                    .font(Theme.ui(Theme.Size.label))
                    .tint(Self.on)
                    .onChange(of: startAtLogin) { _, enabled in setLogin(enabled) }
                if let loginProblem { note(loginProblem, color: Theme.error) }
            }
        }

        ForEach(otherProblems, id: \.self) { note($0, color: Theme.error) }

        let dirty = settings.wrappedValue != model.settings
        HStack(spacing: Theme.Space.m) {
            Button("Revert") { load() }.buttonStyle(FlatButtonStyle()).disabled(!dirty).opacity(dirty ? 1 : 0.4).frame(width: 110)
            Text(saved && !dirty ? (savedNote ?? "Saved.") : "Changes apply when you press Apply.")
                .font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if let checkingHost {
                Text("Checking \(checkingHost)…").font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
            }
            Button("Apply") { apply(settings.wrappedValue) }
                .buttonStyle(FlatButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!dirty || checkingHost != nil)
                .opacity(dirty ? 1 : 0.4)
                .frame(width: 110)
        }
    }

    /// One controller entry: its deck (applied at once, like the panel's picker), devices and channel (#25, #68).
    @ViewBuilder
    private func controllerRows(_ settings: Binding<BridgeSettings>, _ index: Int) -> some View {
        // Bounds-checked: right after a removal, SwiftUI can still read the removed row once.
        let controller = Binding<ControllerSettings>(
            get: { settings.wrappedValue.controllers.indices.contains(index) ? settings.wrappedValue.controllers[index] : Self.newEntry(after: []) },
            set: { if settings.wrappedValue.controllers.indices.contains(index) { settings.wrappedValue.controllers[index] = $0 } }
        )
        heading(settings.wrappedValue.controllers.count > 1 ? "Controller \(index + 1)" : "Controller")
        let following = !model.layers.isEmpty && controller.wrappedValue.followLayers != false
        if !model.layers.isEmpty {
            row("Layers") {
                Toggle("Follow controller layers", isOn: Binding(
                    get: { following },
                    set: { controller.wrappedValue.followLayers = $0 }
                ))
                .font(Theme.ui(Theme.Size.label)).tint(Self.on)
                // The LC6000's own Shift + deck select steps channel 1-4, so it picks deck 1-4 itself (#79).
                if following { hint("Shift + deck select on the controller picks Deck 1-4") }
            }
        }
        if !following {
            row("Deck") {
                DeckPicker(deck: controller.wrappedValue.deck, state: model.status.presentation.deckPicker,
                           problem: model.status.deckProblem) { deck in
                    // The deck applies at once, as in the panel. A saved change reaches the draft through the rebase on
                    // model.settings; a refused one leaves the draft alone and shows why (#90).
                    model.setDeck(deck, controller: index)
                }
                fieldError(.deck(controller: index))
            }
        }
        row("MIDI input") {
            devicePicker(selection: controller.input, devices: sources)
            fieldError(.device(controller: index))
        }
        row("MIDI output") { devicePicker(selection: controller.output, devices: destinations) }
        // Deck and channel come from the controller's layers while it follows them (#79).
        if !following {
            row("Channel") {
                Picker("Channel", selection: controller.channel) {
                    Text("From the profile").tag(Int?.none)
                    ForEach(1...16, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .labelsHidden().fixedSize()
                fieldError(.channel(controller: index))
            }
        }
        if settings.wrappedValue.controllers.count > 1 {
            row("") {
                Button("Remove controller \(index + 1)") { settings.wrappedValue.controllers.remove(at: index) }
                    .buttonStyle(LinkButtonStyle())
            }
        }
    }

    // MARK: Pieces

    /// A section caption across both columns, in natural case; it shows uppercased.
    private func heading(_ title: String) -> some View {
        GridRow {
            Text(title).textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
                .padding(.top, Theme.Space.m)
                .gridCellColumns(2)
        }
    }

    /// A right-aligned caption label and its controls.
    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(label).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.caption)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: Theme.Space.xs) { content() }
        }
    }

    private func devicePicker(selection: Binding<MIDIEndpoint?>, devices: [MIDIEndpoint]) -> some View {
        Picker("Device", selection: selection) {
            Text("Automatic").tag(MIDIEndpoint?.none)
            ForEach(devices) { Text($0.name).tag(MIDIEndpoint?.some($0)) }
            // A saved device that isn't plugged in stays selectable, so the choice isn't lost.
            if let chosen = selection.wrappedValue, !devices.contains(chosen) {
                Text("\(chosen.name) (not connected)").tag(MIDIEndpoint?.some(chosen))
            }
        }
        .labelsHidden()
        .frame(width: 240, alignment: .leading)
    }

    private func field(text: Binding<String>, width: CGFloat, field: SettingsField) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TextField("", text: text).labelsHidden().font(Theme.data(Theme.Size.emphasis)).frame(width: width)
                .overlay(errorBorder(field))
            fieldError(field)
        }
    }

    private func field(value: Binding<Int>, field: SettingsField) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TextField("", value: value, format: .number.grouping(.never)).labelsHidden()
                .font(Theme.data(Theme.Size.emphasis)).frame(width: 80)
                .overlay(errorBorder(field))
            fieldError(field)
        }
    }

    /// A 1 pt error border on a field with a problem (#68).
    @ViewBuilder
    private func errorBorder(_ field: SettingsField) -> some View {
        if fieldProblems.contains(where: { $0.field == field }) {
            RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.error, lineWidth: 1)
        }
    }

    // MARK: Decks (#123)

    /// The deck colors: Syndicate's (cue palette slots 1, 3, 5 and 7) or the DJ's own, each with the LC6000's version.
    @ViewBuilder
    private func decksSection(_ settings: Binding<BridgeSettings>) -> some View {
        heading("Decks")
        row("Colors") {
            Toggle("Use Syndicate's deck colors", isOn: settings.followSyndicateDeckColors)
                .font(Theme.ui(Theme.Size.label)).tint(Self.on)
            hint(settings.wrappedValue.followSyndicateDeckColors
                 ? "Cue palette slots 1, 3, 5 and 7 in Syndicate's CUE COLORS, as they change"
                 : "Your own colors, for the app's badges and the LC6000's ring")
        }
        ForEach(1...4, id: \.self) { deck in
            row("Deck \(deck)") {
                HStack(spacing: Theme.Space.m) {
                    DeckBadgeView(deck: deck)
                    if !settings.wrappedValue.followSyndicateDeckColors {
                        ColorPicker("Deck \(deck) color", selection: Self.color(settings, deck: deck), supportsOpacity: false)
                            .labelsHidden()
                    }
                    // What the LC6000's ring will show: rgb222, so a subtle color may come out plainer.
                    let shown = settings.wrappedValue.followSyndicateDeckColors ? deckColors[deck] : settings.wrappedValue.customDeckColors[deck]
                    RoundedRectangle(cornerRadius: Theme.corner)
                        .fill(Color(RGB(deckColor: DeckColors.ledPreview(shown ?? [0, 0, 0]))))
                        .frame(width: 26, height: 26)
                        .accessibilityLabel("Deck \(deck) on the LC6000")
                    hint("On the LC6000")
                }
                fieldError(.deckColor(deck: deck))
            }
        }
        if !settings.wrappedValue.followSyndicateDeckColors {
            row("") {
                Button("Reset to default") { settings.wrappedValue.customDeckColors = .defaults }.buttonStyle(LinkButtonStyle())
            }
        }
    }

    @Environment(\.deckColors) private var deckColors

    /// A custom deck color as a SwiftUI color, written back as [r, g, b] in sRGB.
    private static func color(_ settings: Binding<BridgeSettings>, deck: Int) -> Binding<Color> {
        Binding(
            get: { Color(RGB(deckColor: settings.wrappedValue.customDeckColors[deck] ?? [0, 0, 0])) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                settings.wrappedValue.customDeckColors.rgb[deck] = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
                    .map { Int(($0 * 255).rounded()) }
            }
        )
    }

    /// The problems that belong to a field, right under it (#68).
    @ViewBuilder
    private func fieldError(_ field: SettingsField) -> some View {
        ForEach(fieldProblems.filter { $0.field == field }, id: \.message) { note($0.message, color: Theme.error) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.ui(Theme.Size.caption)).foregroundStyle(Theme.caption).fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String, color: Color = Theme.caption) -> some View {
        Text(text).font(Theme.ui(Theme.Size.body)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }

    /// With the bridge stopped there is nothing to set: say why in plain words, and offer Diagnostics (#68).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Nothing to set").font(Theme.ui(Theme.Size.title, .bold)).foregroundStyle(Theme.text)
            note(model.status.help?.text ?? "The bridge didn't start. Quit and reopen it.")
            Button("Diagnostics…") {
                NSApp.activate()
                openWindow(id: "diagnostics")
            }
            .buttonStyle(FlatButtonStyle())
            .frame(width: 160)
        }
    }

    /// A switch that's on reads as live, in Syndicate's green, not the system blue (#68). Toggles only: on pickers the
    /// tint would color their text green and read as "live".
    private static let on = Theme.live

    /// A new entry on the first deck no controller drives yet, with automatic devices.
    private static func newEntry(after entries: [ControllerSettings]) -> ControllerSettings {
        let used = Set(entries.map(\.deck))
        return ControllerSettings(deck: (1...4).first { !used.contains($0) } ?? 1, input: nil, output: nil)
    }

    // MARK: Mapping (#24)

    private func importMapping() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a mapping file. A bad file is refused, and the current mapping keeps running."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mappingProblems = model.importMapping(from: url)
        mappingNote = mappingProblems.isEmpty
            ? model.lastImportNote ?? "Imported \(url.lastPathComponent)."
            : "Not imported: fix these and try again."
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

    // MARK: Actions

    private func load() {
        draft = model.settings
        base = model.settings
        sources = model.sources
        destinations = model.destinations
        fieldProblems = []
        otherProblems = []
        saved = false
        startAtLogin = LoginItem.isEnabled
        // A menu-bar app has no Dock icon, so its windows open behind the front app unless it activates.
        NSApp.activate()
    }

    private func apply(_ settings: BridgeSettings) {
        // Field problems are checked here, so they show under their fields; apply checks them all again.
        let problems = settings.fieldProblems
        guard problems.isEmpty else {
            fieldProblems = problems
            otherProblems = []
            return
        }
        // A host name is looked up off the main actor (#84): the window stays usable and says it's checking.
        checkingHost = BridgeSettings.isIPv4(settings.syndicateHost.trimmingCharacters(in: .whitespaces))
            ? nil : settings.syndicateHost.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            defer { checkingHost = nil }
            do throws(SettingsError) {
                savedNote = try await model.apply(settings)
                draft = model.settings
                base = model.settings
                fieldProblems = []
                otherProblems = []
                saved = true
            } catch {
                switch error {
                case .invalid(let list): otherProblems = list
                case .fields(let list): fieldProblems = list
                }
                saved = false
            }
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

/// Brings the window this view is in to the front once it's on screen (#62): a menu-bar app's windows otherwise open
/// behind the front app, and "the first visible window" could be Diagnostics, not this one.
private struct FrontWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.makeKeyAndOrderFront(nil) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
