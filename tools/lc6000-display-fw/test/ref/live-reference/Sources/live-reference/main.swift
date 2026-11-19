// live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> [<level> <peak>] [phase=<n>]
//     [time=<elapsed>/<length>] [look=red|white] <out.ppm> (#459, #461, #462, #460)
// Writes the drawn display as JogDisplayRenderer.drawnImage draws it (#524: drawn mode's own layout) for that deck, with master beat <lit-beat> (1-4) lit and the marker at
// <needle> (0-16383, a turn clockwise from 12 o'clock, as op 09 carries it) and, if given, the level meter at <level>
// with <peak> held (0-127 each, as op 0A carries them), the phase rule at <n> (1/16384 beats, -8191 to 8191, as op 0B
// carries it; with none, the phase is unknown), and the track time in whole seconds as op 06 carries it, in the
// warning's red or white if `look` is given, cropped to the 198×198 frame, as a binary PPM (P6, RGB): the reference
// the drawn display firmware's C tests compare with. "-" is none. The image is opaque, so premultiplied RGBA is RGB.
import ControllerBridgeCore
import ControllerBridgeRender
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let all = Array(CommandLine.arguments.dropFirst())
let flags = Dictionary(all.compactMap { argument -> (String, String)? in
    let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
    return parts.count == 2 && ["time", "look", "phase"].contains(parts[0]) ? (parts[0], parts[1]) : nil
}, uniquingKeysWith: { $1 })
let arguments = all.filter { argument in !["time=", "look=", "phase="].contains { argument.hasPrefix($0) } }
var phase: Int?
if let option = flags["phase"] {
    guard let value = Int(option) else { fail("Bad phase=\(option)") }
    phase = value
}
let usage = "Usage: live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> [<level> <peak>] "
    + "[phase=<n>] [time=<elapsed>/<length>] [look=red|white] <out.ppm>"
guard arguments.count == 8 || arguments.count == 10, let deck = Int(arguments[0]), let r = Int(arguments[1]), let g = Int(arguments[2]),
      let b = Int(arguments[3]) else { fail(usage) }
let litBeat = arguments[5] == "-" ? nil : Int(arguments[5])
let needle = arguments[6] == "-" ? nil : Int(arguments[6])
if arguments[5] != "-" && litBeat == nil || arguments[6] != "-" && needle == nil { fail(usage) }
var meter: DrawnLive.Meter?
if arguments.count == 10 {
    guard let level = Int(arguments[7]), let peak = Int(arguments[8]) else { fail(usage) }
    meter = DrawnLive.Meter(level: level, peak: peak)
}
var time: DrawnLive.Time?
if let value = flags["time"] {
    let parts = value.split(separator: "/").compactMap { Int($0) }
    guard parts.count == 2 else { fail(usage) }
    time = DrawnLive.Time(elapsed: parts[0], length: parts[1])
}
let look: JogTrackTime.Look
switch flags["look"] {
case nil: look = .normal
case "red": look = .warningRed
case "white": look = .warningWhite
default: fail(usage)
}
let output = arguments[arguments.count - 1]
let content = JogDisplayContent(deck: deck, color: [r, g, b], playerType: arguments[4] == "-" ? nil : arguments[4])
let live = DrawnLive(beat: litBeat, needle: needle, meter: meter, phase: phase, time: time, look: look)
let rgba = JogDisplayRenderer.drawnImage(content, live: live)
let size = JogDisplayRenderer.size, drawn = JogDisplayRenderer.drawnSize, inset = (drawn - size) / 2
var ppm = Data("P6\n\(size) \(size)\n255\n".utf8)
for y in 0..<size {
    for x in 0..<size {
        let pixel = (y + inset) * drawn + x + inset
        ppm.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3])
    }
}
do { try ppm.write(to: URL(fileURLWithPath: output)) } catch { fail("Can't write \(output): \(error)") }
