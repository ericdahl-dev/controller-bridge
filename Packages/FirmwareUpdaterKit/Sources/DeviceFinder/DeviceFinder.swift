import FirmwareModel

/// A deck panel the finder saw on USB.
public enum PanelFound: Sendable, Equatable {
    /// On USB, but no driver made a serial port for its chip.
    case driverMissing
    /// On its serial port; the build is nil when its boot line wasn't seen.
    case onSerial(build: PanelBuild?)
}

/// An LC6000 the finder saw. Its firmware isn't read here: nothing is sent to it (#692 checks the unit).
public enum LC6000Found: Sendable, Equatable {
    /// Its MIDI ports are there.
    case onMIDI
    /// ST's ROM bootloader is on USB: any STM32 device in update mode, likely an LC6000's chip.
    case updateMode
}

/// What the finder saw.
public struct Found: Sendable, Equatable {
    public var panel: PanelFound?
    public var lc6000: LC6000Found?

    public init(panel: PanelFound? = nil, lc6000: LC6000Found? = nil) {
        self.panel = panel
        self.lc6000 = lc6000
    }
}

/// Finds a deck panel and an LC6000 (#685). It only looks.
public struct DeviceFinder: Sendable {
    /// The CrowPanel's USB serial chip, a CH340K (tools/deck-panel/README.md).
    static let panelChip = (vendor: UInt16(0x1A86), product: UInt16(0x7522))

    /// The LC6000's MIDI ports carry this in their names, as DeckBridge finds them ("LC6000 PRIME Controller", "… WD").
    static let lc6000Ports = "LC6000 PRIME"
    /// ST's ROM DFU bootloader.
    static let stBootloader = (vendor: UInt16(0x0483), product: UInt16(0xDF11))
    /// How long the finder listens to a panel's serial port for its boot line.
    public static let listenSeconds = 3.0
    static let bootLine = "deck panel: boot, build "
    public static let dirty = "-dirty"

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
        if let chip = devices.first(where: { $0.vendor == Self.panelChip.vendor && $0.product == Self.panelChip.product }) {
            if let port = chip.serialPort {
                found.panel = .onSerial(build: Self.build(in: await serial.listen(on: port, for: Self.listenSeconds)))
            } else {
                found.panel = .driverMissing
            }
        }
        if await midi.names().contains(where: { $0.contains(Self.lc6000Ports) }) {
            found.lc6000 = .onMIDI
        } else if devices.contains(where: { $0.vendor == Self.stBootloader.vendor && $0.product == Self.stBootloader.product }) {
            found.lc6000 = .updateMode
        }
        return found
    }

    /// The build from the panel's boot line, "deck panel: boot, build <sha>": a git short SHA, lowercase hex of 7 to
    /// 40 digits, with "-dirty" on a development build (tools/deck-panel/git_sha.py), kept as printed. "unknown" (a
    /// build made outside git) or anything else is no build.
    static func build(in lines: [String]) -> PanelBuild? {
        for line in lines where line.hasPrefix(bootLine) {
            let printed = line.dropFirst(bootLine.count)
            let sha = printed.hasSuffix(dirty) ? printed.dropLast(dirty.count) : printed
            guard (7...40).contains(sha.count), sha.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
            return PanelBuild(sha: String(printed))
        }
        return nil
    }
}
