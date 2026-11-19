import ControllerBridgeCore
@testable import ControllerBridgeRender
import Foundation
import Testing

/// The drawn display firmware's reference images (tools/lc6000-display-fw/test/ref, #457, #464) are this renderer's
/// output, and the C is checked against them. This checks them against the renderer as it is now, so a design change
/// here (the icon, design B) that isn't carried to the references, and so to the unit, fails.
@Suite("Display firmware references")
struct DisplayFirmwareReferenceTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // the package
        .deletingLastPathComponent().deletingLastPathComponent()                                 // the repo
        .appendingPathComponent("tools/lc6000-display-fw/test/ref")

    /// As test/ref/make_refs.sh renders them.
    static let references: [(file: String, content: JogDisplayContent)] = [
        ("deck2-red-track.ppm", JogDisplayContent(deck: 2, color: [255, 0, 0], playerType: "track")),
        ("deck4-blue-empty.ppm", JogDisplayContent(deck: 4, color: [0, 128, 255], playerType: "empty")),
        ("deck1-white-midi.ppm", JogDisplayContent(deck: 1, color: [255, 255, 255], playerType: "midiclip")),
        ("deck3-green-other.ppm", JogDisplayContent(deck: 3, color: [0, 200, 80])),
        ("deck1-orange-osc.ppm", JogDisplayContent(deck: 1, color: [255, 128, 0], playerType: "osc")),
        ("deck3-purple-seq.ppm", JogDisplayContent(deck: 3, color: [180, 0, 255], playerType: "sequencer")),
        ("stale.ppm", JogDisplayContent(deck: 2, color: [255, 0, 0], playerType: "track", stale: true)),
    ]

    /// A binary PPM's RGB bytes, or nil if it isn't a 198×198 one.
    static func rgb(_ file: String) -> [UInt8]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        let header = Data("P6\n198 198\n255\n".utf8)
        guard data.starts(with: header), data.count == header.count + 198 * 198 * 3 else { return nil }
        return Array(data.dropFirst(header.count))
    }

    /// A few levels of slack, for another Mac's rasterizer; a design change moves far more.
    static let tolerance = 3

    @Test("Each reference is what the renderer draws now", arguments: references.map(\.file))
    func referenceIsCurrent(file: String) throws {
        let content = try #require(Self.references.first { $0.file == file }?.content)
        let reference = try #require(Self.rgb(file), "missing or malformed \(file)")
        let rendered = JogDisplayRenderer.render(content)
        var worst = 0
        for pixel in 0..<(198 * 198) {
            for channel in 0..<3 {
                worst = max(worst, abs(Int(rendered[pixel * 4 + channel]) - Int(reference[pixel * 3 + channel])))
            }
        }
        #expect(worst <= Self.tolerance, "\(file): worst difference \(worst)")
    }
}
