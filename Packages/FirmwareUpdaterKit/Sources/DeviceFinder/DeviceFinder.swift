import FirmwareModel

/// What the finder saw.
public struct Found: Sendable, Equatable {
    public init() {}
}

/// Finds a deck panel and an LC6000 (#685). It only looks.
public struct DeviceFinder: Sendable {
    let usb: any USBDevices
    let midi: any MIDIPorts
    let serial: any PanelSerial
    let log: any LogSink

    public init(usb: any USBDevices, midi: any MIDIPorts, serial: any PanelSerial, log: any LogSink) {
        self.usb = usb
        self.midi = midi
        self.serial = serial
        self.log = log
    }

    public func find() async -> Found {
        Found()
    }
}
