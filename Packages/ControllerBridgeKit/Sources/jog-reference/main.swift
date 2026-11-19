// jog-reference <deck> <r> <g> <b> <player-type|-> <out.ppm> (#457)
// Writes JogDisplayRenderer's upload image for that deck as a binary PPM (P6, RGB): the reference the drawn display
// firmware's C tests compare with. "-" is no player type. The image is opaque, so premultiplied RGBA is plain RGB.
import ControllerBridgeCore
import ControllerBridgeRender
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 6, let deck = Int(arguments[0]), let r = Int(arguments[1]), let g = Int(arguments[2]),
      let b = Int(arguments[3]) else { fail("Usage: jog-reference <deck> <r> <g> <b> <player-type|-> <out.ppm>") }
let content = JogDisplayContent(deck: deck, color: [r, g, b], playerType: arguments[4] == "-" ? nil : arguments[4])
let rgba = JogDisplayRenderer.render(content)
let size = JogDisplayRenderer.size
var ppm = Data("P6\n\(size) \(size)\n255\n".utf8)
for pixel in 0..<(size * size) { ppm.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3]) }
do { try ppm.write(to: URL(fileURLWithPath: arguments[5])) } catch { fail("Can't write \(arguments[5]): \(error)") }
