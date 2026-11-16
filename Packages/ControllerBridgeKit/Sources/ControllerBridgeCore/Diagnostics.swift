import Foundation

/// What the Diagnostics window shows (#26): MIDI in, OSC out and in, and the LED sweep's steps. The Coordinator only
/// builds one while a sink is set (`Coordinator.diagnostics`), so a set without the window open formats nothing.
public enum DiagnosticEvent: Equatable, Sendable {
    /// A message from the controller, with its mapping name or "UNMAPPED", and when it arrived (monotonic seconds).
    case midiIn(MIDIEvent, label: String, at: Double)
    /// OSC sent to Syndicate.
    case oscOut(OSCMessage)
    /// OSC feedback from Syndicate.
    case oscIn(OSCMessage)
    /// A line from the LED sweep, as the Python led-sweep printed it.
    case sweep(String)

    /// The line as the Python bridge printed it, so a hardware check reads the same.
    public var text: String {
        switch self {
        case .midiIn(let event, let label, let time):
            // lc6000_bridge/cli.py: f"{time.monotonic():12.3f}  ch{ch:<2} {str(msg):<50} {label}"
            let channel = String(event.channel + 1).padding(toLength: 2, withPad: " ", startingAt: 0)
            let message = event.midoText.padding(toLength: max(50, event.midoText.count), withPad: " ", startingAt: 0)
            return String(format: "%12.3f", time) + "  ch" + channel + " " + message + " " + label
        // lc6000_bridge/cli.py --verbose: print("OSC ->", address, *args)
        case .oscOut(let message): return (["OSC ->", message.address] + message.arguments.map(\.pythonText)).joined(separator: " ")
        case .oscIn(let message): return (["OSC <-", message.address] + message.arguments.map(\.pythonText)).joined(separator: " ")
        case .sweep(let line): return line
        }
    }
}

extension MIDIEvent {
    var channel: UInt8 {
        switch self {
        case .noteOn(let channel, _, _), .noteOff(let channel, _, _), .controlChange(let channel, _, _): channel
        }
    }

    /// The message as the Python mido library prints it.
    var midoText: String {
        switch self {
        case .noteOn(let channel, let note, let velocity): "note_on channel=\(channel) note=\(note) velocity=\(velocity) time=0"
        case .noteOff(let channel, let note, let velocity): "note_off channel=\(channel) note=\(note) velocity=\(velocity) time=0"
        case .controlChange(let channel, let controller, let value): "control_change channel=\(channel) control=\(controller) value=\(value) time=0"
        }
    }
}

extension Mapping {
    /// The mapping name of a message, as the Python monitor printed it: a button name, "pad1"…"pad8", a CC name, or
    /// "UNMAPPED". Any channel.
    func monitorName(for event: MIDIEvent) -> String {
        switch event {
        case .noteOn(_, let note, _), .noteOff(_, let note, _):
            let note = Int(note)
            if let pad = notes.pads.firstIndex(of: note) { return "pad\(pad + 1)" }
            return notes.buttons.first { $0.value == note }?.key ?? "UNMAPPED"
        case .controlChange(_, let controller, _):
            let cc = Int(controller)
            if jog.ccs.contains(cc) { return "jog" }
            let named: [(Int, String)] = [
                (pitch.msbCC, "pitch_msb"), (pitch.lsbCC, "pitch_lsb"), (needle.cc, "needle"),
                (browse.selectTurnCC, "select_turn"), (browse.autoLoopSizeCC, "auto_loop_size"),
            ]
            return named.first { $0.0 == cc }?.1 ?? "UNMAPPED"
        }
    }
}

extension OSCArgument {
    /// As Python prints the decoded value: an int, a float as its shortest round-trip repr ("0.25", "128.0"), a string.
    var pythonText: String {
        switch self {
        case .int(let value): String(value)
        case .float(let value): String(Double(value))
        case .string(let value): value
        }
    }
}

/// Passes OSC on to the real sender, and to the OSC log while Diagnostics is open.
final class OSCTap: OSCSender, @unchecked Sendable {
    private let inner: any OSCSender
    /// Set and read only on the Coordinator's one consumer.
    var onSend: ((OSCMessage) -> Void)?

    init(_ inner: any OSCSender) { self.inner = inner }

    func send(_ message: OSCMessage) {
        inner.send(message)
        onSend?(message)
    }
}
