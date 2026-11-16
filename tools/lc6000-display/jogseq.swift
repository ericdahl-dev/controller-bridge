import CoreMIDI
import Foundation

// Sends a jog-display plan to the LC6000 (#121, #165), listening on both of its ports. Plan lines:
//   <delay ms> WD  <hex…>      send to "Denon DJ LC6000 PRIME WD" (jog SysEx, ch1 pitch bend, ch1 note 1)
//   <delay ms> CTL <hex…>      send to the Controller (Serato SysEx 00 20 7F only)
//   <delay ms> ACKS <n> <timeout ms>   wait until n `01 10 0F` acks have arrived on WD since the last ACKS
//   # comment
// `dry <plan>` checks and prints the plan, sends nothing. `send <plan>` sends it once, listening on both sources.
let wdName = "Denon DJ LC6000 PRIME WD"
let ctlName = "Denon DJ LC6000 PRIME LC6000 PRIME Controller"

func name(_ e: MIDIEndpointRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s)
    return (s?.takeRetainedValue() as String?) ?? "?"
}
/// One SysEx message (F0 … F7) as UMP SysEx7 packets of two words each: the bytes between F0 and F7, six at a time.
func sysex7Packets(_ message: [UInt8]) -> [[UInt32]] {
    let body = Array(message.dropFirst().dropLast())
    let pieces = stride(from: 0, to: max(body.count, 1), by: 6).map { Array(body[$0..<min($0 + 6, body.count)]) }
    return pieces.enumerated().map { index, piece in
        let status: UInt32 = pieces.count == 1 ? 0 : index == 0 ? 1 : index == pieces.count - 1 ? 3 : 2
        let b = piece.map(UInt32.init) + Array(repeating: 0, count: 6 - piece.count)
        return [0x3000_0000 | status << 20 | UInt32(piece.count) << 16 | b[0] << 8 | b[1],
                b[2] << 24 | b[3] << 16 | b[4] << 8 | b[5]]
    }
}

func hex(_ b: [UInt8], _ n: Int = 12) -> String {
    b.prefix(n).map { String(format: "%02X", $0) }.joined(separator: " ") + (b.count > n ? " … (\(b.count) B)" : "")
}

enum Step { case send(port: String, bytes: [UInt8]); case acks(count: Int, timeoutMs: Int) }
let args = CommandLine.arguments
if args.count == 2 && args[1] == "selftest" {
    // UMP SysEx7 (MIDI 2.0 spec, type 3): up to 6 bytes a packet; status 0 complete, 1 start, 2 continue, 3 end.
    func hex(_ packets: [[UInt32]]) -> String { packets.map { $0.map { String(format: "%08X", $0) }.joined(separator: " ") }.joined(separator: " | ") }
    let identity = sysex7Packets([0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7])
    let thirteen = sysex7Packets([0xF0] + Array(1...13).map(UInt8.init) + [0xF7])
    let checks = [
        (hex(identity), "30047E00 06010000"),
        (hex(thirteen), "30160102 03040506 | 30260708 090A0B0C | 30310D00 00000000"),
        (hex(sysex7Packets([0xF0, 1, 2, 3, 4, 5, 6, 0xF7])), "30060102 03040506"),
        (hex(sysex7Packets([0xF0, 0xF7])), "30000000 00000000"),
    ]
    for (got, want) in checks where got != want { print("FAIL: \(got) != \(want)"); exit(1) }
    print("selftest ok")
    exit(0)
}
guard args.count == 3, ["dry", "send", "burst"].contains(args[1]) else { print("usage: dry|send|burst <plan> | selftest"); exit(2) }
// send: SysEx through MIDISendSysex, which paces it at MIDI 1.0 speed (31250 baud, about 3.1 KB/s).
// burst: SysEx as UMP packets through MIDISendEventList, at USB speed, as djay sends it (#165); acks are checked after.
let burst = args[1] == "burst"
var plan: [(delay: Int, step: Step)] = []
for (n, raw) in try String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").enumerated() {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty || line.hasPrefix("#") { continue }
    let p = line.split(separator: " ").map(String.init)
    func fail(_ why: String) -> Never { print("ABORT line \(n + 1): \(why): \(line)"); exit(1) }
    guard p.count >= 3, let delay = Int(p[0]) else { fail("bad line") }
    switch p[1] {
    case "ACKS":
        guard let c = Int(p[2]), p.count == 4, let t = Int(p[3]) else { fail("ACKS <n> <timeout ms>") }
        plan.append((delay, .acks(count: c, timeoutMs: t)))
    case "WD", "CTL":
        let bytes = p.dropFirst(2).map { UInt8($0, radix: 16) }
        guard bytes.allSatisfy({ $0 != nil }) else { fail("not hex (placeholder still in the plan?)") }
        let b = bytes.map { $0! }
        let sysexOK = b.first == 0xF0 && b.last == 0xF7 && b.dropFirst().dropLast().allSatisfy { $0 < 0x80 }
        if p[1] == "CTL" {
            // Serato SysEx, or the Denon host message a DJ app sends at launch (cmd 60).
            let hostHello: [UInt8] = [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x60, 0x00, 0x04, 0x04, 0x01, 0x01, 0x00, 0xF7]
            // A host's launch also sends LED note-ons on ch1-4 and identity requests to the Controller.
            let ledNote = b.count == 3 && (0x90...0x93).contains(b[0]) && b[1] < 0x80 && b[2] < 0x80
            let identity = b == [0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7]
            guard ledNote || identity || (sysexOK && (Array(b[1...3]) == [0x00, 0x20, 0x7F] || b == hostHello)) else {
                fail("Controller takes only Serato SysEx, the cmd 60 host hello, LED note-ons or an identity request")
            }
        } else {
            let denon = sysexOK && Array(b[1...5]) == [0x00, 0x02, 0x0B, 0x7F, 0x10]
            let identity = b == [0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7]
            // What a host sends the jog display besides SysEx (#165): the platter marker as pitch bend on ch1, and the
            // play/cue state as note 1 on ch1.
            let marker = b.count == 3 && b[0] == 0xE0 && b[1] < 0x80 && b[2] < 0x80
            let playState = b.count == 3 && b[0] == 0x90 && b[1] == 0x01 && b[2] < 0x80
            guard denon || identity || marker || playState else {
                fail("WD takes 00 02 0B 7F 10 SysEx, an identity request, pitch bend on ch1, or note 1 on ch1")
            }
        }
        plan.append((delay, .send(port: p[1], bytes: b)))
    default: fail("port must be WD, CTL or ACKS")
    }
}
for (i, s) in plan.enumerated() {
    switch s.step {
    case .send(let port, let b): print("plan #\(i) +\(s.delay) ms \(port): \(hex(b))")
    case .acks(let c, let t): print("plan #\(i) +\(s.delay) ms wait for \(c) acks (max \(t) ms)")
    }
}
if args[1] == "dry" { exit(0) }

let dests = (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }
let sources = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }
func one(_ list: [MIDIEndpointRef], _ n: String) -> MIDIEndpointRef {
    let m = list.filter { name($0) == n }
    guard m.count == 1 else { print("ABORT: \(m.count) endpoints named \(n)"); exit(1) }
    return m[0]
}
let dest = ["WD": one(dests, wdName), "CTL": one(dests, ctlName)]
let wdSource = one(sources, wdName), ctlSource = one(sources, ctlName)

var client = MIDIClientRef()
guard MIDIClientCreateWithBlock("jog-seq" as CFString, &client, nil) == noErr else { print("ABORT: client"); exit(1) }
var outPort = MIDIPortRef()
guard MIDIOutputPortCreate(client, "out" as CFString, &outPort) == noErr else { print("ABORT: out port"); exit(1) }

final class Acks: @unchecked Sendable {
    let lock = NSLock(); var count = 0; var refused = false
    func add() { lock.withLock { count += 1 } }
    func refuse() { lock.withLock { refused = true } }
    var anyRefused: Bool { lock.withLock { refused } }
    func take() -> Int { lock.withLock { defer { count = 0 }; return count } }
}
let acks = Acks()
let t0 = Date()
func since() -> String { String(format: "+%8.3f s", Date().timeIntervalSince(t0)) }

/// Rebuilds SysEx from UMP SysEx7 packets, per source; logs every complete message and voice message.
final class Reassembler: @unchecked Sendable {
    let label: String; var buf: [UInt8] = []
    init(_ label: String) { self.label = label }
    func feed(_ words: [UInt32]) {
        var i = 0
        while i < words.count {
            let w0 = words[i], type = w0 >> 28
            if type == 3, i + 1 < words.count {
                let w1 = words[i + 1], status = (w0 >> 20) & 0xF, n = Int((w0 >> 16) & 0xF)
                let bytes = [UInt8((w0 >> 8) & 0xFF), UInt8(w0 & 0xFF), UInt8(w1 >> 24), UInt8((w1 >> 16) & 0xFF),
                             UInt8((w1 >> 8) & 0xFF), UInt8(w1 & 0xFF)].prefix(n)
                if status == 0 || status == 1 { buf = [] }
                buf += bytes
                if status == 0 || status == 3 {
                    let msg = [0xF0] + buf + [0xF7]
                    // An ack is 01 10 0F 00 01 <status>: 00 accepted; anything else (06 seen) is a refusal.
                    if Array(buf.prefix(6)) == [0x00, 0x02, 0x0B, 0x01, 0x10, 0x0F] {
                        if buf.last == 0x00 { acks.add() } else { acks.refuse() }
                    }
                    print("\(since()) RECV \(label): \(hex(msg, 40))")
                }
                i += 2
            } else if type == 2 {
                let b = [UInt8((w0 >> 16) & 0xFF), UInt8((w0 >> 8) & 0xFF), UInt8(w0 & 0xFF)]
                // The heartbeat (note 52 every 300 ms) would drown the log.
                if !(b[0] & 0xF0 == 0x90 && b[1] == 0x34) { print("\(since()) RECV \(label): \(hex(b))") }
                i += 1
            } else { i += [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4][Int(type)] }
        }
    }
}
let wdIn = Reassembler("WD"), ctlIn = Reassembler("CTL")
var inPort = MIDIPortRef()
guard MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &inPort, { list, ref in
    let r = Unmanaged<Reassembler>.fromOpaque(ref!).takeUnretainedValue()
    for packet in list.unsafeSequence() { r.feed(Array(packet.words())) }
}) == noErr,
      MIDIPortConnectSource(inPort, wdSource, Unmanaged.passUnretained(wdIn).toOpaque()) == noErr,
      MIDIPortConnectSource(inPort, ctlSource, Unmanaged.passUnretained(ctlIn).toOpaque()) == noErr
else { print("ABORT: listen"); exit(1) }

final class Done: @unchecked Sendable { var flag = false }
func send(_ bytes: [UInt8], to d: MIDIEndpointRef) -> Bool {
    if bytes.first != 0xF0 {
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        let word = 0x2000_0000 | UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, [word])
        return MIDISendEventList(outPort, d, &list) == noErr
    }
    if burst { return sendBurst(bytes, to: d) }
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    buffer.initialize(from: bytes, count: bytes.count)
    defer { buffer.deallocate() }
    let done = Done()
    let req = UnsafeMutablePointer<MIDISysexSendRequest>.allocate(capacity: 1)
    defer { req.deallocate() }
    req.initialize(to: MIDISysexSendRequest(destination: d, data: UnsafePointer(buffer), bytesToSend: UInt32(bytes.count),
        complete: false, reserved: (0, 0, 0), completionProc: { r in
            Unmanaged<Done>.fromOpaque(r.pointee.completionRefCon!).takeUnretainedValue().flag = true
        }, completionRefCon: Unmanaged.passUnretained(done).toOpaque()))
    guard MIDISendSysex(req) == noErr else { return false }
    let deadline = Date().addingTimeInterval(15)
    while !done.flag && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return done.flag && req.pointee.bytesToSend == 0
}

/// Sends a SysEx message as UMP SysEx7 packets without waiting: 512 packets (1024 words, about 4.3 KB of event
/// list) per MIDIEventList, well inside its 64 KB buffer.
func sendBurst(_ bytes: [UInt8], to d: MIDIEndpointRef) -> Bool {
    let capacity = 65536
    let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)
    let packets = sysex7Packets(bytes)
    for start in stride(from: 0, to: packets.count, by: 512) {
        var packet = MIDIEventListInit(list, ._1_0)
        for words in packets[start..<min(start + 512, packets.count)] {
            packet = MIDIEventListAdd(list, capacity, packet, 0, words.count, words)
        }
        guard MIDISendEventList(outPort, d, list) == noErr else { return false }
    }
    return true
}

print("\(since()) listening on WD and CTL")
var acked = 0
for (i, s) in plan.enumerated() {
    RunLoop.current.run(until: Date().addingTimeInterval(Double(s.delay) / 1000))
    switch s.step {
    case .send(let port, let b):
        let ok = send(b, to: dest[port]!)
        print("\(since()) SENT #\(i) \(port): \(hex(b)) \(ok ? "ok" : "FAILED")")
        if !ok { print("STOP: send failed; the rest not sent"); exit(1) }
    case .acks(let c, let t):
        let deadline = Date().addingTimeInterval(Double(t) / 1000)
        while acked < c && Date() < deadline && !acks.anyRefused {
            acked += acks.take()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        acked += acks.take()
        print("\(since()) ACKS \(acked)/\(c)")
        if acks.anyRefused { print("STOP: the unit refused (ack status not 00); the rest not sent"); exit(1) }
        if acked < c { print("STOP: acks missing; the rest not sent"); exit(1) }
        acked = 0
    }
}
RunLoop.current.run(until: Date().addingTimeInterval(3))
print("\(since()) done")
