#if DEBUG
// Renders the panel in a few states to PNGs, for PR screenshots: `ControllerBridge --render-snapshots <name>`.
// The app is sandboxed, so the PNGs go to <container tmp>/<name>; the path is printed. Compiled out of Release.
import AppKit
import ControllerBridgeCore
import ControllerBridgePresentation
import SwiftUI

@MainActor
enum Snapshots {
    static func render(to name: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name).path
        for font in ["Inter-Regular", "Inter-SemiBold", "Inter-Bold", "IBMPlexMono", "IBMPlexMono-Medm", "IBMPlexMono-SmBld"] {
            print("\(font): \(NSFont(name: font, size: 12) == nil ? "MISSING" : "ok")")
        }
        let states: [(String, (BridgeStatus) -> Void)] = [
            ("connected", {
                $0.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME")]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
            }),
            // Syndicate stopped answering (#21): DROPPED, and the last dropout under the lights.
            ("feedback-dropped", {
                $0.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME")]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .stale
                $0.lastDropout = "Syndicate feedback stopped"
                $0.lastDropoutTime = "21:14"
            }),
            ("connected-master-others", {
                $0.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME", master: true)]
                $0.devices = [
                    DeviceStatus(name: "Denon LC6000 PRIME", profile: "Denon LC6000 PRIME", note: nil),
                    DeviceStatus(name: "IAC Bus 1", profile: nil, note: nil),
                    DeviceStatus(name: "loopMIDI Port", profile: nil, note: nil),
                ]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
            }),
            // Never connected since launch: gray NOT CONNECTED (#66).
            ("not-connected", {
                $0.bridges = [ControllerStatus(deck: 2, connected: false)]
                $0.devices = [
                    DeviceStatus(name: "DDJ-FLX4", profile: nil, note: "No controller profile matches DDJ-FLX4, so it isn't bridged."),
                    DeviceStatus(name: "IAC Bus 1", profile: nil, note: nil),
                ]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
            }),
            ("port-in-use", {
                $0.bridges = [ControllerStatus(deck: 3, connected: true, profile: "Denon LC6000 PRIME")]
                $0.feedback = .portInUse(port: 9096)
            }),
            // The built-in demo controller (#64): DEMO leads, so it is never mistaken for hardware.
            ("demo", {
                $0.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME")]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
                $0.demo = true
            }),
            // Connected earlier, then pulled mid-set: orange UNPLUGGED (#66).
            ("unplugged", {
                $0.bridges = [ControllerStatus(deck: 1, connected: false, lastEvent: "Disconnected DENON LC6000 PRIME")]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
            }),
            // Two controllers (#25): a block and a deck picker each; the status line lists both decks.
            ("two-controllers", {
                $0.bridges = [
                    ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME"),
                    ControllerStatus(deck: 3, connected: true, profile: "Denon LC6000 PRIME"),
                ]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
            }),
            ("starting-deck4", { $0.deck = 4 }),
            ("many-lights", {
                $0.bridges = [ControllerStatus(deck: 2, connected: true, profile: "Denon LC6000 PRIME", master: true)]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .live
                $0.problem = "Couldn't open the OSC sender: connect: Network is unreachable"
            }),
            ("waiting", {
                $0.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME")]
                $0.feedback = .listening(port: 9096)
                $0.syndicateFeedback = .waiting
            }),
            ("stopped", { $0.problem = "Couldn't start CoreMIDI: status(\"MIDIClientCreateWithBlock\", -10844)" }),
        ]
        do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) } catch {
            print("Couldn't create \(directory): \(error)"); return
        }
        write(buttonStates, to: "\(directory)/buttons.png")
        for (name, configure) in states {
            let status = BridgeStatus()
            configure(status)
            write(StatusPanel(status: status), to: "\(directory)/panel-\(name).png")
            if name == "connected" || name == "waiting" {
                write(SetupGuideView(guide: status.setupGuide, presentation: status.presentation), to: "\(directory)/setup-guide-\(name).png")
            }
            write(icons(status.presentation.icon), to: "\(directory)/icon-\(name).png")
        }
        // Settings (#68), through an NSHostingView: ImageRenderer can't draw its AppKit controls.
        let defaults = BridgeSettings.defaults(from: try! ControllerProfile.bundled()[0].mapping)
        writeAppKit(SettingsView(model: BridgeModel(preview: defaults)), to: "\(directory)/settings.png")
        var two = defaults
        two.controllers.append(ControllerSettings(deck: 3, input: nil, output: nil))
        writeAppKit(SettingsView(model: BridgeModel(preview: two)), to: "\(directory)/settings-two-controllers.png")
        let stopped = BridgeModel(preview: nil)
        stopped.status.problem = "Couldn't start CoreMIDI"
        writeAppKit(SettingsView(model: stopped), to: "\(directory)/settings-stopped.png")
        // The Diagnostics window (#26), with lines as the Kit formats them.
        let log = DiagnosticsLog()
        let monitor: [MIDIEvent] = [
            .noteOn(channel: 0, note: 1, velocity: 127), .noteOff(channel: 0, note: 1, velocity: 0),
            .noteOn(channel: 0, note: 32, velocity: 127), .controlChange(channel: 0, controller: 55, value: 1),
            .controlChange(channel: 0, controller: 99, value: 64),
        ]
        for (index, event) in monitor.enumerated() {
            log.append(.midiIn(event, label: ["play", "play", "pad1", "jog", "UNMAPPED"][index], at: 1234.5 + Double(index) * 0.1))
        }
        for line in ["Color sweep: velocity shown on every pad and the ring. Note what each looks like.",
                     "  velocity  0 (0x00) = rgb222 r0 g0 b0", "  velocity  1 (0x01) = rgb222 r0 g0 b1"] {
            log.append(.sweep(line))
        }
        log.append(.oscOut(OSCMessage("/Syndicate/Deck/1/PlayPause", [.int(1)])))
        log.append(.oscIn(OSCMessage("/Syndicate/Deck/1/Playing", [.int(1)])))
        log.append(.oscIn(OSCMessage("/Syndicate/Deck/1/Progress", [.float(0.25)])))
        // A connected controller with its LED output open, and one with no controller at all (#70).
        let connected = BridgeStatus()
        connected.bridges = [ControllerStatus(deck: 1, connected: true, profile: "Denon LC6000 PRIME", outputOpen: true)]
        connected.feedback = .listening(port: 9096)
        connected.syndicateFeedback = .live
        let empty = DiagnosticsLog()
        for tab in DiagnosticsWindow.Tab.allCases {
            let name = tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            let window = DiagnosticsWindow(
                log: log, status: connected, sweeping: tab == .sweep, setOpen: { _ in }, startSweep: { _ in }, stopSweep: {},
                tab: tab, scrolls: false
            )
            write(window.frame(width: 720, height: 460), to: "\(directory)/diagnostics-\(name).png")
            let blank = DiagnosticsWindow(
                log: empty, status: BridgeStatus(), sweeping: false, setOpen: { _ in }, startSweep: { _ in }, stopSweep: {},
                tab: tab, scrolls: false
            )
            write(blank.frame(width: 720, height: 460), to: "\(directory)/diagnostics-\(name)-empty.png")
        }
    }

    /// The shared button styles (#67): normal, selected (bar + heavier text) and keyboard focus (ring).
    private static var buttonStates: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                Button("Normal") {}.buttonStyle(FlatButtonStyle())
                Button("Selected") {}.buttonStyle(FlatButtonStyle(selected: true))
                Button("Focused") {}.buttonStyle({ var style = FlatButtonStyle(); style.showsFocusForSnapshot = true; return style }())
            }
            Button("Setup guide…") {}.buttonStyle(LinkButtonStyle())
        }
        .padding(Theme.Space.xl)
        .frame(width: 360)
        .background(Theme.panel)
    }

    private static func icons(_ state: IconState) -> some View {
        // The template icon on a light and a dark menu bar.
        HStack(spacing: 0) {
            Image(nsImage: MenuBarIcon.image(state)).renderingMode(.template).foregroundStyle(.black)
                .padding(6).background(Color(white: 0.92))
            Image(nsImage: MenuBarIcon.image(state)).renderingMode(.template).foregroundStyle(.white)
                .padding(6).background(Color(white: 0.15))
        }
    }

    /// Renders through a hosting view's display cache, which draws AppKit-backed controls (pickers, text fields).
    private static func writeAppKit(_ view: some View, to path: String) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        // Lay out tall first, so the fitting height is the whole form, then shrink to it.
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 2000)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: NSSize(width: 440, height: host.fittingSize.height))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("Couldn't render \(path)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("Couldn't render \(path)"); return }
        do { try png.write(to: URL(fileURLWithPath: path)); print("Wrote \(path)") } catch { print("Couldn't write \(path): \(error)") }
    }

    private static func write(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("Couldn't render \(path)"); return
        }
        do { try png.write(to: URL(fileURLWithPath: path)); print("Wrote \(path)") } catch { print("Couldn't write \(path): \(error)") }
    }
}

#endif
