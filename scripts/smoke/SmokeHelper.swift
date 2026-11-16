// Stands in for the LC6000 (a virtual MIDI source and destination) and for Syndicate (UDP 9090 in, 9096 out).
// Run by scripts/smoke.sh. Exits 0 when Play goes out as PlayPause and the Play LED comes back, 1 otherwise.
import CoreMIDI
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
func say(_ line: String) { print("[smoke] \(line)") }
func fail(_ line: String) -> Never { say("FAIL: \(line)"); exit(1) }

func hex(_ text: String) -> [UInt8] {
    let digits = text.filter(\.isHexDigit)
    return stride(from: 0, to: digits.count, by: 2).map {
        let start = digits.index(digits.startIndex, offsetBy: $0)
        return UInt8(digits[start...digits.index(after: start)], radix: 16)!
    }
}
// Worked by hand from the OSC 1.0 spec.
let resend = hex("2f53796e 64696361 74652f46 65656462 61636b2f 52657365 6e640000 2c690000 00000001") // /Syndicate/Feedback/Resend ,i 1
let playPause = hex("2f53796e 64696361 74652f44 65636b2f 312f506c 61795061 75736500 2c690000 00000001") // /Syndicate/Deck/1/PlayPause ,i 1
let playing = hex("2f53796e 64696361 74652f44 65636b2f 312f506c 6179696e 67000000 2c690000 00000001") // /Syndicate/Deck/1/Playing ,i 1
let playLEDFull: UInt32 = 0x2090_017F // note on, channel 1, note 1 (Play), velocity 127

final class Box: @unchecked Sendable {
    let lock = NSLock()
    var datagrams: [[UInt8]] = []
    var words: [UInt32] = []
    func add(datagram: [UInt8]) { lock.withLock { datagrams.append(datagram) } }
    func add(words: [UInt32]) { lock.withLock { self.words += words } }
    var snapshot: ([[UInt8]], [UInt32]) { lock.withLock { (datagrams, words) } }
}
let box = Box()

func waitFor(_ what: String, seconds: Double, _ done: () -> Bool) {
    let deadline = Date().addingTimeInterval(seconds)
    while !done() {
        if Date() > deadline { fail("timed out waiting for \(what). Saw: \(box.snapshot)") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    say("ok: \(what)")
}

// MIDI: the app matches endpoints whose name contains "LC6000".
var client = MIDIClientRef()
guard MIDIClientCreateWithBlock("LC6000 smoke" as CFString, &client, nil) == noErr else { fail("MIDI client") }
var destination = MIDIEndpointRef()
guard MIDIDestinationCreateWithProtocol(client, "LC6000 Smoke" as CFString, ._1_0, &destination, { list, _ in
    for packet in list.unsafeSequence() { box.add(words: Array(packet.words())) }
}) == noErr else { fail("virtual destination") }
var source = MIDIEndpointRef()
guard MIDISourceCreateWithProtocol(client, "LC6000 Smoke" as CFString, ._1_0, &source) == noErr else { fail("virtual source") }

// UDP: fake Syndicate's OSC input on 9090.
func loopback(_ port: UInt16) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return address
}
func withSockaddr<R>(_ address: sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
    withUnsafePointer(to: address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
}
let inbound = socket(AF_INET, SOCK_DGRAM, 0)
guard withSockaddr(loopback(9090), { bind(inbound, $0, $1) }) == 0 else { fail("bind 127.0.0.1:9090: \(String(cString: strerror(errno)))") }
Thread.detachNewThread {
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        let count = recv(inbound, &buffer, buffer.count, 0)
        if count > 0 { box.add(datagram: Array(buffer[0..<count])) }
    }
}
say("READY")

// 1. The app starts: it asks Syndicate to resend its state.
let launchTimeout = Double(CommandLine.arguments.dropFirst().first ?? "20")!
waitFor("Feedback/Resend from the app", seconds: launchTimeout) { box.snapshot.0.contains(resend) }

// 2. Press Play on the "controller": PlayPause 1 goes to Syndicate.
var list = MIDIEventList()
let packet = MIDIEventListInit(&list, ._1_0)
var press: UInt32 = 0x2090_017F
_ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &press)
MIDIReceivedEventList(source, &list)
waitFor("PlayPause 1 at 127.0.0.1:9090", seconds: 5) { box.snapshot.0.contains(playPause) }

// 3. "Syndicate" reports Playing 1 on the feedback port: the Play LED goes full.
let outbound = socket(AF_INET, SOCK_DGRAM, 0)
_ = playing.withUnsafeBytes { bytes in withSockaddr(loopback(9096)) { sendto(outbound, bytes.baseAddress, bytes.count, 0, $0, $1) } }
waitFor("Play LED full (\(String(format: "%08X", playLEDFull))) on the controller", seconds: 5) { box.snapshot.1.contains(playLEDFull) }

say("PASS")
exit(0)
