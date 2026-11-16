// Drives the capture window (#186): the Kit's CaptureFlow, fed by the capture MIDI input or the demo controller.
// Not unit-tested: every rule lives in CaptureFlow (Kit), and the live path is on the manual checklist.
import ControllerBridgeCapture
import ControllerBridgeCore
import Foundation
import SwiftUI

@MainActor @Observable
final class CaptureController {
    /// A port the owner can pick: a real source, or the demo controller.
    struct Choice: Hashable, Identifiable {
        var name: String
        var endpoint: MIDIEndpoint?
        var id: String { name }
    }

    private(set) var flow = CaptureFlow(appVersion: CaptureController.appVersion)
    /// The host time, refreshed every second for the idle countdown.
    private(set) var now = ProcessInfo.processInfo.systemUptime
    var picked: Choice?
    private(set) var choices: [Choice] = []

    private var input: CaptureMIDIInput?
    private var paused: MIDIEndpoint.ID?
    private var demoTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private let setCapture: (MIDIEndpoint.ID?) -> Void
    private var destinations: [MIDIEndpoint] = []

    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// `setCapture` pauses (a source) or gives back (nil) a controller in the bridge.
    init(setCapture: @escaping (MIDIEndpoint.ID?) -> Void) {
        self.setCapture = setCapture
    }

    #if DEBUG
    /// Snapshots only: a flow already in some state, at a fixed time.
    init(flow: CaptureFlow, now: Double, choices: [Choice] = [], picked: Choice? = nil) {
        self.flow = flow
        self.now = now
        self.choices = choices
        self.picked = picked
        setCapture = { _ in }
    }
    #endif

    /// Lists the ports, with the demo controller last. Called when the window opens.
    func refresh(sources: [MIDIEndpoint], destinations: [MIDIEndpoint]) {
        guard flow.phase == .ports else { return }
        self.destinations = destinations
        choices = sources.map { Choice(name: $0.name, endpoint: $0) } + [Choice(name: DemoCapture.deviceName, endpoint: nil)]
        if picked.map(choices.contains) != true { picked = choices.first }
    }

    func start() {
        guard let picked else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if let endpoint = picked.endpoint {
            let all = choices.compactMap(\.endpoint)
            let ports = CapturePorts.suggested(for: picked.name, sources: all.map(\.name), destinations: destinations.map(\.name))
            let listened = ports.input.compactMap { name in all.first { $0.name == name } }
            paused = endpoint.id
            setCapture(endpoint.id)
            input = CaptureMIDIInput(sources: listened) { [weak self] bytes, time, port in
                Task { @MainActor in self?.receive(bytes, at: time, port: port) }
            }
            flow.start(device: picked.name, ports: ports, at: time)
        } else {
            flow.start(device: DemoCapture.deviceName, ports: DemoCapture.ports, at: time)
        }
        startClock()
        stepChanged()
    }

    func next() { act { flow.next(at: $0) } }
    func redo() { act { flow.redo(at: $0) } }
    func skip() { act { flow.skip(at: $0) } }

    var canNext: Bool { flow.canNext(at: now) }
    var idleSecondsLeft: Int? { flow.idleSecondsLeft(at: now) }

    /// Ends the capture: the bridge gets the controller back, and nothing more is heard. Safe to call twice.
    func end() {
        input?.stop()
        input = nil
        demoTask?.cancel()
        clockTask?.cancel()
        if paused != nil { setCapture(nil) }
        paused = nil
    }

    private func act(_ change: (Double) -> Void) {
        let time = ProcessInfo.processInfo.systemUptime
        now = time
        change(time)
        stepChanged()
        if flow.phase == .done { end() }
    }

    private func receive(_ bytes: [UInt8], at time: Double, port: Int) {
        flow.receive(bytes, at: time, port: port)
        announce()
    }

    /// A new step or a redo: announce it, and play the demo controller's answer if it's the one being captured.
    private func stepChanged() {
        announce()
        guard flow.file?.device == DemoCapture.deviceName, let prompt = flow.prompt else { return }
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            let start = ProcessInfo.processInfo.systemUptime + 1
            for message in DemoCapture.take(for: prompt) {
                let at = start + message.time
                try? await Task.sleep(for: .seconds(max(0, at - ProcessInfo.processInfo.systemUptime)))
                guard !Task.isCancelled else { return }
                self?.receive(message.bytes, at: at, port: 0)
            }
        }
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.now = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    private func announce() {
        guard let text = flow.takeAnnouncement() else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
