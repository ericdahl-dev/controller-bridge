// The LC6000 jog display's ports in CoreMIDI (#165). Not unit-tested: the driver and Coordinator are tested in the
// Kit through JogDisplayPort; the hardware check covers this. SysEx goes out as UMP SysEx7 at USB speed, as djay sends
// it (#168); the WD port's answers are reassembled and go into the pipe, in order with everything else.
import CoreMIDI
import ControllerBridgeCore
import Synchronization

/// Sends to the unit's WD port and its Controller port, found by name on each send so a replug just works; listens to
/// the WD port for the unit's upload answers. Nothing is sent unless the Coordinator's switch is on.
final class CoreMIDIJogDisplay: JogDisplayPort {
    /// The unit's two ports, as CoreMIDI names them: "… LC6000 PRIME WD" and "… LC6000 PRIME Controller".
    static let wdHint = "LC6000 PRIME WD"
    static let controllerHint = "LC6000 PRIME Controller"

    private let output: MIDIPortRef
    private let input: MIDIPortRef
    private let listening = Mutex<MIDIUniqueID?>(nil)

    /// Makes the ports on the app's MIDI client. Must run on the main thread, as the client was.
    @MainActor
    init(client: MIDIClientRef, producer: EventPipe.Producer) throws {
        var output = MIDIPortRef()
        try check("MIDIOutputPortCreate", MIDIOutputPortCreate(client, "Jog display out" as CFString, &output))
        var input = MIDIPortRef()
        try check("MIDIInputPortCreateWithProtocol", MIDIInputPortCreateWithProtocol(
            client, "Jog display in" as CFString, ._1_0, &input, Self.receiveBlock(SysExAssembler(producer))
        ))
        self.output = output
        self.input = input
    }

    /// Connects the WD source, when it's there and not yet connected: before each WD send, so the answers to it are
    /// heard, after a replug too.
    private func listen() {
        guard let source = Self.find(sources: true, hint: Self.wdHint) else { return }
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id)
        let isNew = listening.withLock { current in
            defer { current = id }
            return current != id
        }
        if isNew { MIDIPortConnectSource(input, source, nil) }
    }

    /// The WD port is there now (#305): without it, nothing is sent and no upload is waited on.
    var isAttached: Bool { Self.find(sources: false, hint: Self.wdHint) != nil }

    func sendController(_ bytes: [UInt8]) { send(bytes, hint: Self.controllerHint) }
    func sendWD(_ bytes: [UInt8]) {
        listen()
        send(bytes, hint: Self.wdHint)
    }

    private func send(_ bytes: [UInt8], hint: String) {
        guard let destination = Self.find(sources: false, hint: hint) else { return }
        let words: [[UInt32]] = bytes.first == 0xF0 ? Self.sysex7(bytes) : [[Self.voice(bytes)]]
        // At most 512 packets a list, about 4 KB of SysEx: big enough to be fast, small enough for any buffer.
        let capacity = 1024 * 4 * 8 + 1024
        let list = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8).bindMemory(to: MIDIEventList.self, capacity: 1)
        defer { list.deallocate() }
        for start in stride(from: 0, to: words.count, by: 512) {
            var packet = MIDIEventListInit(list, ._1_0)
            for packetWords in words[start..<min(start + 512, words.count)] {
                packet = MIDIEventListAdd(list, capacity, packet, 0, packetWords.count, packetWords)
            }
            MIDISendEventList(output, destination, list)
        }
    }

    /// A SysEx message (F0 … F7) as UMP SysEx7 packets of two words: the bytes between F0 and F7, six at a time.
    static func sysex7(_ message: [UInt8]) -> [[UInt32]] {
        let body = Array(message.dropFirst().dropLast())
        let pieces = stride(from: 0, to: max(body.count, 1), by: 6).map { Array(body[$0..<min($0 + 6, body.count)]) }
        return pieces.enumerated().map { index, piece in
            let status: UInt32 = pieces.count == 1 ? 0 : index == 0 ? 1 : index == pieces.count - 1 ? 3 : 2
            let b = piece.map(UInt32.init) + Array(repeating: 0, count: 6 - piece.count)
            return [0x3000_0000 | status << 20 | UInt32(piece.count) << 16 | b[0] << 8 | b[1],
                    b[2] << 24 | b[3] << 16 | b[4] << 8 | b[5]]
        }
    }

    /// A three-byte channel message (pitch bend, a note) as one UMP type 2 word.
    static func voice(_ bytes: [UInt8]) -> UInt32 {
        let b = bytes + [0, 0, 0]
        return 0x2000_0000 | UInt32(b[0]) << 16 | UInt32(b[1] & 0x7F) << 8 | UInt32(b[2] & 0x7F)
    }

    private static func find(sources: Bool, hint: String) -> MIDIEndpointRef? {
        let count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations()
        for index in 0..<count {
            let ref = sources ? MIDIGetSource(index) : MIDIGetDestination(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name)
            if let text = name?.takeRetainedValue() as String?, text.contains(hint) { return ref }
        }
        return nil
    }

    private nonisolated static func receiveBlock(_ assembler: SysExAssembler) -> MIDIReceiveBlock {
        { list, _ in
            for packet in list.unsafeSequence() { assembler.feed(Array(packet.words())) }
        }
    }
}

/// Rebuilds SysEx from UMP SysEx7 packets and hands each whole message to the pipe.
final class SysExAssembler: Sendable {
    private let producer: EventPipe.Producer
    private let buffer = Mutex<[UInt8]>([])

    init(_ producer: EventPipe.Producer) { self.producer = producer }

    func feed(_ words: [UInt32]) {
        var index = 0
        while index + 1 < words.count {
            let first = words[index], second = words[index + 1]
            index += 2
            guard first >> 28 == 3 else { continue }
            let status = first >> 20 & 0xF, count = Int(first >> 16 & 0xF)
            let bytes = [UInt8(first >> 8 & 0xFF), UInt8(first & 0xFF), UInt8(second >> 24), UInt8(second >> 16 & 0xFF),
                         UInt8(second >> 8 & 0xFF), UInt8(second & 0xFF)].prefix(count)
            let whole: [UInt8]? = buffer.withLock { buffer in
                if status == 0 || status == 1 { buffer = [] }
                buffer += bytes
                guard status == 0 || status == 3 else { return nil }
                return [0xF0] + buffer + [0xF7]
            }
            if let whole { producer.jogDisplayReply(whole) }
        }
    }
}

private func check(_ call: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CoreMIDIError.status(call, status) }
}
