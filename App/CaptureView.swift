// The guided "Help add a controller" window (#186): a thin view over the Kit's CaptureFlow. Bodies stay small for the
// CI Xcode 26.6 optimizer (#65).
import ControllerBridgeCapture
import ControllerBridgeCore
import SwiftUI

enum CaptureWindow {
    static let id = "capture"
    static let title = "Help Add a Controller"
}

/// The window's root: makes the controller, lists the ports when it opens, and gives the bridge back when it closes.
struct CaptureWindowRoot: View {
    let model: BridgeModel
    @State private var controller: CaptureController?

    var body: some View {
        Group {
            if let controller { CaptureView(controller: controller) } else { Theme.panel.frame(width: 480, height: 360) }
        }
        .onAppear {
            // A fresh capture each time the window opens: one closed mid-way has already given its controller back.
            let made = CaptureController(setCapture: model.setCapture(source:))
            made.refresh(sources: model.sources, destinations: model.destinations)
            controller = made
        }
        .onDisappear { controller?.end() }
    }
}

struct CaptureView: View {
    @Bindable var controller: CaptureController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x4) {
            switch controller.flow.phase {
            case .ports: CapturePortsPage(controller: controller)
            case .steps: CaptureStepPage(controller: controller)
            case .done: CaptureDonePage(file: controller.flow.file)
            }
        }
        .padding(Theme.Step.x6)
        .frame(width: 480, alignment: .topLeading)
        .background(Theme.panel)
    }
}

/// An eyebrow label over a headline, as the setup guide's.
private struct CaptureHeading: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x1) {
            Text(eyebrow).font(Theme.labelFont).foregroundStyle(Theme.caption)
            Text(title).font(Theme.ui(22, .medium)).tracking(-0.8).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

private struct CapturePortsPage: View {
    @Bindable var controller: CaptureController

    var body: some View {
        CaptureHeading(eyebrow: "Help add a controller", title: "Capture your controller")
        Text("DeckBridge listens while you press, move and turn each control, and records what it sends. Nothing is sent to your controller or anywhere else. It takes about five minutes.")
            .font(Theme.ui(13)).foregroundStyle(Theme.caption)
            .fixedSize(horizontal: false, vertical: true)
        Picker("Controller", selection: $controller.picked) {
            ForEach(controller.choices) { Text($0.name).tag(Optional($0)) }
        }
        .font(Theme.ui(13))
        Text("While it captures, DeckBridge stops sending this controller's moves to Syndicate.")
            .font(Theme.ui(12)).foregroundStyle(Theme.caption)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Start") { controller.start() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(controller.picked == nil)
        }
    }
}

private struct CaptureStepPage: View {
    let controller: CaptureController

    var body: some View {
        let flow = controller.flow
        CaptureHeading(eyebrow: "Step \(flow.stepNumber) of \(flow.stepCount)", title: flow.prompt?.text ?? "")
        CaptureReadout(detected: flow.detected, idleSecondsLeft: controller.idleSecondsLeft)
        HStack(spacing: Theme.Step.x2) {
            Button("Redo") { controller.redo() }
                .buttonStyle(PillButtonStyle())
                .disabled(!flow.canRedo)
            Button("Skip") { controller.skip() }
                .buttonStyle(PillButtonStyle(kind: .quiet))
                .disabled(!flow.canSkip)
            Spacer()
            Button("Next") { controller.next() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.canNext)
        }
    }
}

/// What the step has detected so far, live.
private struct CaptureReadout: View {
    let detected: [ControlFacts]
    let idleSecondsLeft: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x2) {
            Text("Detected").font(Theme.labelFont).foregroundStyle(Theme.caption)
            if let idleSecondsLeft {
                line(idleSecondsLeft > 0 ? "Listening… Next in \(idleSecondsLeft) s" : "Done listening", color: Theme.caption)
            } else if detected.isEmpty {
                line("Waiting for the control…", color: Theme.caption)
            } else {
                ForEach(Array(detected.enumerated()), id: \.offset) { line($0.element.summary, color: Theme.text) }
            }
        }
        .padding(Theme.Step.x4)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(text).font(Theme.data(13)).foregroundStyle(color)
    }

    private var accessibilityText: String {
        if let idleSecondsLeft { return idleSecondsLeft > 0 ? "Listening, Next in \(idleSecondsLeft) seconds" : "Done listening" }
        if detected.isEmpty { return "Detected: nothing yet" }
        return "Detected: " + detected.map(\.spoken).joined(separator: ", then ")
    }
}

private struct CaptureDonePage: View {
    let file: CaptureFile?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let steps = file?.steps ?? []
        let skipped = steps.filter { $0.status == .skipped }.count
        CaptureHeading(eyebrow: "Help add a controller", title: "Capture finished")
        let demo = file?.device == DemoCapture.deviceName
        Text("\(steps.count) steps captured, \(skipped) skipped." + (demo ? "" : " DeckBridge is sending this controller's moves to Syndicate again."))
            .font(Theme.ui(13)).foregroundStyle(Theme.caption)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("Close") { dismissWindow(id: CaptureWindow.id) }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }
}
