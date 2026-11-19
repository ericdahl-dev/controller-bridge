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

    /// Slack for another Mac's rasterizer: CI's macOS draws text edges up to about 40 levels off this renderer's on
    /// a developer's Mac, and nothing else. So most pixels must be within a few levels, a bounded number of text edge
    /// pixels may be further off, and none by more than `cap`. A design change (a color, a size, a shape) moves far
    /// more pixels than the budget.
    static let close = 3, budget = 400, cap = 64

    @Test("Each reference is what the renderer draws now", arguments: references.map(\.file))
    func referenceIsCurrent(file: String) throws {
        let content = try #require(Self.references.first { $0.file == file }?.content)
        let reference = try #require(Self.rgb(file), "missing or malformed \(file)")
        let rendered = JogDisplayRenderer.render(content)
        var worst = 0, loose = 0
        for pixel in 0..<(198 * 198) {
            var difference = 0
            for channel in 0..<3 {
                difference = max(difference, abs(Int(rendered[pixel * 4 + channel]) - Int(reference[pixel * 3 + channel])))
            }
            worst = max(worst, difference)
            if difference > Self.close { loose += 1 }
        }
        print("\(file): worst \(worst), \(loose) pixels over \(Self.close)")
        #expect(worst <= Self.cap && loose <= Self.budget, "\(file): worst \(worst), \(loose) pixels over \(Self.close)")
    }
}
