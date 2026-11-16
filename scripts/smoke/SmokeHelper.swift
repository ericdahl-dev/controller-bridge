// Stands in for the LC6000 and for Syndicate (UDP 9090 in, 9096 out). Like the real unit, it has two MIDI ports: the
// controls port and a "… WD" port (jog displays) that macOS lists first. The app must never send LEDs to WD.
// Run by scripts/smoke.sh. Exits 0 when Play goes out as PlayPause, the Play LED comes back on the controls port on
// layer 1 and, after a switch, on layer 2, and the WD port gets nothing. Exits 1 otherwise.
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
let playing2 = hex("2f53796e 64696361 74652f44 65636b2f 322f506c 6179696e 67000000 2c690000 00000001") // /Syndicate/Deck/2/Playing ,i 1
let playLEDFullLayer2: UInt32 = 0x2091_017F // note on, channel 2, note 1 (Play), velocity 127

final class Box: @unchecked Sendable {
    let lock = NSLock()
    var datagrams: [[UInt8]] = []
    var words: [UInt32] = []
    var wdWords: [UInt32] = []
    func add(datagram: [UInt8]) { lock.withLock { datagrams.append(datagram) } }
    func add(words: [UInt32]) { lock.withLock { self.words += words } }
    func add(wdWords: [UInt32]) { lock.withLock { self.wdWords += wdWords } }
    var wd: [UInt32] { lock.withLock { wdWords } }
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

// MIDI: named like the real unit's ports ("Denon DJ LC6000 PRIME LC6000 PRIME Controller" and its "… WD" twin), but
// with "Smoke", so they never match a real LC6000 plugged into this Mac. The profile matches "LC6000" and excludes
// "LC6000 PRIME WD". The WD pair is made first, so it is listed first, as macOS lists the real one.
let controlsName = "Smoke LC6000 PRIME Controller", wdName = "Smoke LC6000 PRIME WD Controller"
var client = MIDIClientRef()
guard MIDIClientCreateWithBlock("LC6000 smoke" as CFString, &client, nil) == noErr else { fail("MIDI client") }

// With no real LC6000 here, the app runs with automatic devices, as on a real unit, so it must pick the controls ports
// over the WD ones itself (#143). With one attached, automatic devices could pick it, so the script pins the app to
// the helper's controls ports instead (#86) and the automatic case is skipped. CI has no controller: it always runs
// the automatic case.
func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
    return name?.takeRetainedValue() as String? ?? ""
}
let present = (0..<MIDIGetNumberOfSources()).map { endpointName(MIDIGetSource($0)) }
    + (0..<MIDIGetNumberOfDestinations()).map { endpointName(MIDIGetDestination($0)) }
let realController = present.first(where: { $0.localizedCaseInsensitiveContains("LC6000") })
let mode = realController == nil ? "automatic" : "pinned"
if let realController { say("WD/automatic case skipped: real controller attached (\(realController))") }

var wdDestination = MIDIEndpointRef()
guard MIDIDestinationCreateWithProtocol(client, wdName as CFString, ._1_0, &wdDestination, { list, _ in
    for packet in list.unsafeSequence() { box.add(wdWords: Array(packet.words())) }
}) == noErr else { fail("virtual WD destination") }
var wdSource = MIDIEndpointRef()
guard MIDISourceCreateWithProtocol(client, wdName as CFString, ._1_0, &wdSource) == noErr else { fail("virtual WD source") }
var destination = MIDIEndpointRef()
guard MIDIDestinationCreateWithProtocol(client, controlsName as CFString, ._1_0, &destination, { list, _ in
    for packet in list.unsafeSequence() { box.add(words: Array(packet.words())) }
}) == noErr else { fail("virtual destination") }
var source = MIDIEndpointRef()
guard MIDISourceCreateWithProtocol(client, controlsName as CFString, ._1_0, &source) == noErr else { fail("virtual source") }

/// Sends one MIDI 1.0 word from the "controller".
func play(_ word: UInt32) {
    var list = MIDIEventList()
    let packet = MIDIEventListInit(&list, ._1_0)
    var word = word
    _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
    MIDIReceivedEventList(source, &list)
}
func sendFeedback(_ datagram: [UInt8]) {
    _ = datagram.withUnsafeBytes { bytes in withSockaddr(loopback(9096)) { sendto(outbound, bytes.baseAddress, bytes.count, 0, $0, $1) } }
}

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
// The unique ids of the helper's endpoints: the script pins the app to them (#86), so a real controller plugged into
// this Mac can't take their place. The app's input is the helper's source, and its output the helper's destination.
func uniqueID(_ endpoint: MIDIEndpointRef) -> Int32 {
    var id: Int32 = 0
    MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
    return id
}
let outbound = socket(AF_INET, SOCK_DGRAM, 0)
say("READY mode=\(mode) input=\(uniqueID(source)) output=\(uniqueID(destination)) name=\(controlsName)")

// 1. The app starts: it asks Syndicate to resend its state.
let launchTimeout = Double(CommandLine.arguments.dropFirst().first ?? "20")!
waitFor("Feedback/Resend from the app", seconds: launchTimeout) { box.snapshot.0.contains(resend) }

// 2. Press Play on the "controller": PlayPause 1 goes to Syndicate.
play(0x2090_017F)
waitFor("PlayPause 1 at 127.0.0.1:9090", seconds: 5) { box.snapshot.0.contains(playPause) }

// 3. "Syndicate" reports Playing 1 on the feedback port: the Play LED goes full.
sendFeedback(playing)
waitFor("Play LED full (\(String(format: "%08X", playLEDFull))) on the controls port", seconds: 5) { box.snapshot.1.contains(playLEDFull) }

// 4. Deck 2 plays, and the DJ switches the unit to layer 2 (deck select: ch1 note 51 off, ch2 note 51 on, then a
// control on ch2). Layer 2's Play LED comes on, on ch2 and on the controls port: every layer shares it (#79).
sendFeedback(playing2)
play(0x2090_3300)
play(0x2091_337F)
play(0x2081_0100)
waitFor("layer 2's Play LED full (\(String(format: "%08X", playLEDFullLayer2))) on the controls port", seconds: 5) {
    box.snapshot.1.contains(playLEDFullLayer2)
}

// 5. Nothing ever went to the WD port: there, note 1 also resets a jog display.
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
guard box.wd.isEmpty else { fail("the app sent \(box.wd.count) MIDI words to the WD port: \(box.wd.prefix(8).map { String(format: "%08X", $0) })") }
say("ok: nothing on the WD port")

say("PASS")
exit(0)
