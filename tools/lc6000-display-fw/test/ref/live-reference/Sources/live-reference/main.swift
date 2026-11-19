// live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> [<level> <peak>] [phase=<n>] <out.ppm>
// (#459, #461, #462)
// Writes JogDisplayRenderer's simulator image for that deck, with master beat <lit-beat> (1-4) lit and the marker at
// <needle> (0-16383, a turn clockwise from 12 o'clock, as op 09 carries it) and, if given, the level meter at <level>
// with <peak> held (0-127 each, as op 0A carries them) and, if given, the phase rule at <n> (1/16384 beats, -8191 to 8191,
// as op 0B carries it; with none, the phase is unknown), as a binary PPM (P6, RGB): the reference
// the drawn display firmware's C tests compare with. "-" is none. The image is opaque, so premultiplied RGBA is RGB.
import ControllerBridgeCore
import ControllerBridgeRender
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var phase: Int?
if let option = arguments.first(where: { $0.hasPrefix("phase=") }) {
    guard let value = Int(option.dropFirst(6)) else { fail("Bad \(option)") }
    phase = value
    arguments.removeAll { $0 == option }
}
let usage = "Usage: live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> [<level> <peak>] [phase=<n>] <out.ppm>"
guard arguments.count == 8 || arguments.count == 10, let deck = Int(arguments[0]), let r = Int(arguments[1]), let g = Int(arguments[2]),
      let b = Int(arguments[3]) else { fail(usage) }
let litBeat = arguments[5] == "-" ? nil : Int(arguments[5])
let needle = arguments[6] == "-" ? nil : Int(arguments[6])
if arguments[5] != "-" && litBeat == nil || arguments[6] != "-" && needle == nil { fail(usage) }
var meter: (level: Int, peak: Int)?
if arguments.count == 10 {
    guard let level = Int(arguments[7]), let peak = Int(arguments[8]) else { fail(usage) }
    meter = (level, peak)
}
let output = arguments[arguments.count - 1]
let content = JogDisplayContent(deck: deck, color: [r, g, b], playerType: arguments[4] == "-" ? nil : arguments[4])
let rgba = JogDisplayRenderer.simulatorImage(content, litBeat: litBeat, marker: needle.map { Double($0) / 16384 },
                                                meter: meter, phase: phase)
let size = JogDisplayRenderer.size
var ppm = Data("P6\n\(size) \(size)\n255\n".utf8)
for pixel in 0..<(size * size) { ppm.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3]) }
do { try ppm.write(to: URL(fileURLWithPath: output)) } catch { fail("Can't write \(output): \(error)") }
