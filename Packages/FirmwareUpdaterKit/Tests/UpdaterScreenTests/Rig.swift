import DeviceFinder
import Foundation
import UpdaterScreen

/// Fake ports: what the test plugs in. Each records what it was asked.
final class FakeUSB: USBDevices, @unchecked Sendable {
    var plugged: [USBDevice] = []
    func devices() async -> [USBDevice] { plugged }
}

final class FakeMIDI: MIDIPorts, @unchecked Sendable {
    var ports: [String] = []
    func names() async -> [String] { ports }
}

final class FakeSerial: PanelSerial, @unchecked Sendable {
    /// What the panel prints on each port while the app listens.
    var lines: [String: [String]] = [:]
    func listen(on port: String, for seconds: Double) async -> [String] { lines[port] ?? [] }
}

final class FakeLog: LogSink, @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    func log(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

struct Rig {
    let usb = FakeUSB()
    let midi = FakeMIDI()
    let serial = FakeSerial()
    let log = FakeLog()

    var finder: DeviceFinder { DeviceFinder(usb: usb, midi: midi, serial: serial, log: log) }

    func screen(lc6000WarningAccepted: Bool = true) async -> UpdaterScreen {
        UpdaterScreen(found: await finder.find(), lc6000WarningAccepted: lc6000WarningAccepted)
    }
}
