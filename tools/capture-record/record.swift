// Records a controller's MIDI for the capture tests (#185), step by step, LISTEN-ONLY.
//
// It creates a CoreMIDI input port and no output port, so it cannot send anything to the hardware, not even the
// host hello. Keep DeckBridge running if you want the LC6000 in host mode (its note 52 heartbeat is part of the
// fixture), and pause Syndicate first: pressing Play still drives it through DeckBridge.
//
//   swift tools/capture-record/record.swift "LC6000" > lc6000-recording.json
//
// Each step: do what the prompt says, then press Return to keep it, type r + Return to redo, or s + Return to skip.
// The output is {"device", "sources", "steps": [{"prompt", "status", "take": [[seconds, source, "90 01 7F"], ...]}]},
// where source is an index into "sources" (the LC6000's main port and its WD port are separate sources).
import CoreMIDI
import Foundation

// The same ids and words as the Kit's CapturePrompts.djController (#186), so the recording replays through it (#213).
let hotcues: [(id: String, text: String)] = (1...8).map { ("deck1.hotcue\($0)", "In Hot Cue mode, press and release pad \($0) on deck 1.") }
let prompts: [(id: String, text: String)] = [
    ("idle", "Don't touch anything for 5 seconds."),
    ("deck1.play", "Press and release Play on deck 1."),
    ("deck1.cue", "Press and release Cue on deck 1."),
    ("deck1.sync", "Press and release Sync on deck 1."),
] + hotcues + [
    ("deck1.pitch", "Move the pitch fader slowly all the way from the top to the bottom."),
    ("deck1.jog.touch", "Touch the top of the jog wheel, turn it right a quarter turn, then left, then let go."),
    ("deck1.jog.edge", "Without touching the top, spin the jog wheel's edge right, then left."),
    ("deck1.needle", "Touch the needle strip at the left, slide slowly to the right, then let go."),
    ("deck1.loop_in", "Press and release Loop In on deck 1."),
    ("deck1.loop_out", "Press and release Loop Out on deck 1."),
    ("deck1.auto_loop", "Press and release Auto Loop on deck 1."),
    ("deck1.browse.turn", "Turn the browse knob right three clicks, then left three clicks."),
    ("deck1.browse.press", "Press and release the browse knob."),
    ("deck1.shift", "Press and release Shift on deck 1."),
    ("deck1.play.shift", "Hold Shift, press and release Play, then let go of Shift."),
    ("deck1.cue.shift", "Hold Shift, press and release Cue, then let go of Shift."),
    ("deck1.hotcue1.shift", "Hold Shift, press and release pad 1, then let go of Shift."),
    ("layer2.select", "Switch the left side to deck 2 (its deck or layer button)."),
    ("deck2.play", "Press and release Play on deck 2."),
]

let match = CommandLine.arguments.dropFirst().first ?? "LC6000"
let lock = NSLock()
nonisolated(unsafe) var take: [(Double, Int, String)] = []

func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

/// MIDI 1.0 bytes from Universal MIDI Packet words: channel voice (type 2) and system real-time / common (type 1).
/// SysEx and the rest are skipped.
func messages(_ words: [UInt32]) -> [[UInt8]] {
    let lengths = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
    var out: [[UInt8]] = []
    var i = 0
    while i < words.count {
        let w = words[i], type = Int(w >> 28)
        if type == 1 {
            let status = UInt8((w >> 16) & 0xFF)
            out.append(status >= 0xF8 ? [status] : [status, UInt8((w >> 8) & 0x7F), UInt8(w & 0x7F)])
        } else if type == 2 {
            let status = UInt8((w >> 16) & 0xFF), d1 = UInt8((w >> 8) & 0x7F), d2 = UInt8(w & 0x7F)
            out.append(status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0 ? [status, d1] : [status, d1, d2])
        }
        i += lengths[type]
    }
    return out
}

var client = MIDIClientRef()
var port = MIDIPortRef()
guard MIDIClientCreateWithBlock("capture-record" as CFString, &client, nil) == noErr,
    MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &port, { list, refCon in
        let now = ProcessInfo.processInfo.systemUptime
        let source = Int(bitPattern: refCon) - 1
        for packet in list.unsafeSequence() {
            let words = Array(packet.words())
            lock.lock()
            for bytes in messages(words) { take.append((now, source, bytes.map { String(format: "%02X", $0) }.joined(separator: " "))) }
            lock.unlock()
        }
    }) == noErr
else { log("Couldn't open CoreMIDI."); exit(1) }

var sources: [String] = []
for index in 0..<MIDIGetNumberOfSources() {
    let source = MIDIGetSource(index)
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
    let display = name?.takeRetainedValue() as String? ?? ""
    guard display.contains(match) else { continue }
    MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: sources.count + 1))
    sources.append(display)
}
guard !sources.isEmpty else { log("No MIDI source matches \"\(match)\"."); exit(1) }
log("Listening (never sending) to: \(sources.joined(separator: ", "))")

var steps: [[String: Any]] = []
var index = 0
while index < prompts.count {
    let prompt = prompts[index]
    lock.lock(); take = []; lock.unlock()
    log("\n[\(index + 1)/\(prompts.count)] \(prompt.text)\n  Return = keep, r = redo, s = skip")
    let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    lock.lock(); let kept = take; lock.unlock()
    if answer == "r" { continue }
    let skipped = answer == "s"
    let start = kept.first?.0 ?? 0
    steps.append([
        "prompt": prompt.id, "status": skipped ? "skipped" : "confirmed",
        "take": skipped ? [] : kept.map { [(($0.0 - start) * 1000).rounded() / 1000, $0.1, $0.2] as [Any] },
    ])
    log("  \(skipped ? "skipped" : "kept \(kept.count) messages")")
    index += 1
}

let output: [String: Any] = ["device": match, "sources": sources, "steps": steps]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
