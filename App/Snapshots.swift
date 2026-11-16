#if DEBUG
// Renders the panel in a few states to PNGs, for PR screenshots: `ControllerBridge --render-snapshots <name>`.
// The app is sandboxed, so the PNGs go to <container tmp>/<name>; the path is printed. Compiled out of Release.
import AppKit
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
            ("connected", { $0.controllers = ["DENON LC6000 PRIME"]; $0.feedback = .listening(port: 9096) }),
            ("not-connected", { $0.feedback = .listening(port: 9096); $0.deck = 2 }),
            ("port-in-use", { $0.controllers = ["DENON LC6000 PRIME"]; $0.feedback = .portInUse(port: 9096); $0.deck = 3 }),
            ("starting-deck4", { $0.deck = 4 }),
            ("stopped", { $0.problem = "Couldn't start CoreMIDI: status(\"MIDIClientCreateWithBlock\", -10844)" }),
        ]
        do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) } catch {
            print("Couldn't create \(directory): \(error)"); return
        }
        for (name, configure) in states {
            let status = BridgeStatus()
            configure(status)
            write(StatusPanel(status: status), to: "\(directory)/panel-\(name).png")
            write(icons(status.presentation.icon), to: "\(directory)/icon-\(name).png")
        }
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
