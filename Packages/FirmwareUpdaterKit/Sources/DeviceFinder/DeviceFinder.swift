import FirmwareModel

/// A deck panel the finder saw on USB.
public enum PanelFound: Sendable, Equatable {
    /// On USB, but no driver made a serial port for its chip.
    case driverMissing
}

/// What the finder saw.
public struct Found: Sendable, Equatable {
    public var panel: PanelFound?

    public init(panel: PanelFound? = nil) {
        self.panel = panel
    }
}

/// Finds a deck panel and an LC6000 (#685). It only looks.
public struct DeviceFinder: Sendable {
    /// The CrowPanel's USB serial chip, a CH340K (tools/deck-panel/README.md).
    static let panelChip = (vendor: UInt16(0x1A86), product: UInt16(0x7522))

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
        let devices = await usb.devices()
        var found = Found()
        if devices.contains(where: { $0.vendor == Self.panelChip.vendor && $0.product == Self.panelChip.product }) {
            found.panel = .driverMissing
        }
        return found
    }
}
