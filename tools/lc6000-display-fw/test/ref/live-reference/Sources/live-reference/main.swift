// live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> <out.ppm> (#459)
// Writes JogDisplayRenderer's simulator image for that deck, with master beat <lit-beat> (1-4) lit and the marker at
// <needle> (0-16383, a turn clockwise from 12 o'clock, as op 09 carries it), as a binary PPM (P6, RGB): the reference
// the drawn display firmware's C tests compare with. "-" is none. The image is opaque, so premultiplied RGBA is RGB.
import ControllerBridgeCore
import ControllerBridgeRender
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = "Usage: live-reference <deck> <r> <g> <b> <player-type|-> <lit-beat|-> <needle|-> <out.ppm>"
guard arguments.count == 8, let deck = Int(arguments[0]), let r = Int(arguments[1]), let g = Int(arguments[2]),
      let b = Int(arguments[3]) else { fail(usage) }
let litBeat = arguments[5] == "-" ? nil : Int(arguments[5])
let needle = arguments[6] == "-" ? nil : Int(arguments[6])
if arguments[5] != "-" && litBeat == nil || arguments[6] != "-" && needle == nil { fail(usage) }
let content = JogDisplayContent(deck: deck, color: [r, g, b], playerType: arguments[4] == "-" ? nil : arguments[4])
let rgba = JogDisplayRenderer.simulatorImage(content, litBeat: litBeat, marker: needle.map { Double($0) / 16384 })
let size = JogDisplayRenderer.size
var ppm = Data("P6\n\(size) \(size)\n255\n".utf8)
for pixel in 0..<(size * size) { ppm.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3]) }
do { try ppm.write(to: URL(fileURLWithPath: arguments[7])) } catch { fail("Can't write \(arguments[7]): \(error)") }
