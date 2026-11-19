// jog-reference <deck> <r> <g> <b> <player-type|-> <out.ppm> [stale] [title=…] [artist=…] [key=…] [bpm=…]
// (#457, #464, #458)
// Writes JogDisplayRenderer's upload image for that deck as a binary PPM (P6, RGB): the reference the drawn display
// firmware's C tests compare with. "-" is no player type; "stale" draws the waiting look. The image is opaque, so premultiplied RGBA is plain RGB.
import ControllerBridgeCore
import ControllerBridgeRender
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = "Usage: jog-reference <deck> <r> <g> <b> <player-type|-> <out.ppm> [stale] [title=…] [artist=…] [key=…] [bpm=…]"
guard arguments.count >= 6, let deck = Int(arguments[0]), let r = Int(arguments[1]), let g = Int(arguments[2]),
      let b = Int(arguments[3]) else { fail(usage) }
var content = JogDisplayContent(deck: deck, color: [r, g, b], playerType: arguments[4] == "-" ? nil : arguments[4])
for option in arguments.dropFirst(6) {
    if option == "stale" { content.stale = true; continue }
    guard let equals = option.firstIndex(of: "=") else { fail(usage) }
    let value = String(option[option.index(after: equals)...])
    switch option[..<equals] {
    case "title": content.title = value
    case "artist": content.artist = value
    case "key": content.key = value
    case "bpm": guard let bpm = Double(value) else { fail(usage) }; content.bpm = bpm
    default: fail(usage)
    }
}
let rgba = JogDisplayRenderer.render(content)
let size = JogDisplayRenderer.size
var ppm = Data("P6\n\(size) \(size)\n255\n".utf8)
for pixel in 0..<(size * size) { ppm.append(contentsOf: rgba[pixel * 4..<pixel * 4 + 3]) }
do { try ppm.write(to: URL(fileURLWithPath: arguments[5])) } catch { fail("Can't write \(arguments[5]): \(error)") }
