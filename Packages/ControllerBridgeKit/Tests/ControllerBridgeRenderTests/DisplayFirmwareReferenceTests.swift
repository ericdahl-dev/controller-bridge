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
        // The text (#458): a short title, one line at 20 px, two lines, cut lines with no key or BPM, and accents.
        ("text-strobe.ppm", JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Strobe", artist: "Deadmau5", key: "F#m",
                                              bpm: 128, playerType: "track")),
        ("text-night-drive.ppm", JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Night Drive", artist: "Café del Mar",
                                                   key: "11B", bpm: 90, playerType: "track")),
        ("text-ten.ppm", JogDisplayContent(deck: 1, color: [255, 255, 255], title: "Ten (Original Club Mix)",
                                           artist: "Mark Knight", key: "8A", bpm: 124.5, playerType: "track")),
        ("text-cut.ppm", JogDisplayContent(deck: 3, color: [0, 200, 80],
                                           title: "Mark Knight Underworld Sander Van Doorn Remix Edition",
                                           artist: "Wolfgang Amadeus Mozart and the Vienna Philharmonic", playerType: "track")),
        ("text-accents.ppm", JogDisplayContent(deck: 4, color: [0, 128, 255], title: "Tänzer aus Tübingen",
                                               artist: "Léa Seydoux & “Don’t”", key: "Ebm", bpm: 174, playerType: "track")),
        // An untitled deck of another kind: its own name, "no title", and key and BPM ("—" for both).
        ("text-automation.ppm", JogDisplayContent(deck: 3, color: [0, 200, 80], playerType: "Automation")),
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
    /// more pixels than the budget. Measured on CI (macos-26): worst 41, at most 51 pixels over 3; locally all exact.
    static let close = 3, budget = 150, cap = 64

    @Test("Each reference is what the renderer draws now", arguments: references.map(\.file))
    func referenceIsCurrent(file: String) throws {
        let content = try #require(Self.references.first { $0.file == file }?.content)
        try compare(file, with: Self.drawnFrame(content))
    }

    /// The drawn display's 198 frame (#524): drawnImage, drawn mode's own layout, cropped to the frame, RGBA, as
    /// make_refs.sh's tools write it. The chip draws drawn mode only.
    static func drawnFrame(_ content: JogDisplayContent, live: DrawnLive = DrawnLive()) -> [UInt8] {
        let rgba = JogDisplayRenderer.drawnImage(content, live: live)
        let size = JogDisplayRenderer.size, drawn = JogDisplayRenderer.drawnSize, inset = (drawn - size) / 2
        var out: [UInt8] = []
        out.reserveCapacity(size * size * 4)
        for y in 0..<size {
            let row = ((y + inset) * drawn + inset) * 4
            out += rgba[row..<row + size * 4]
        }
        return out
    }

    /// The phase rule's references (#462), as make_refs.sh renders them with live-reference: deck 4, empty, blue.
    @Test("Each phase reference is what the renderer draws now", arguments: [0, -164, 164, -1638, 8191])
    func phaseReferenceIsCurrent(phase: Int) throws {
        let content = JogDisplayContent(deck: 4, color: [0, 128, 255], playerType: "empty")
        let file = "deck4-blue-empty-phase\(phase).ppm", rendered = Self.drawnFrame(content, live: DrawnLive(phase: phase))
        try compare(file, with: rendered)
        // The rule's rows hold no text, so no rasterizer slack: every pixel there within `close`.
        let reference = try #require(Self.rgb(file))
        var off = 0
        for pixel in 124 * 198..<132 * 198 {
            for channel in 0..<3 {
                let difference = abs(Int(rendered[pixel * 4 + channel]) - Int(reference[pixel * 3 + channel]))
                if difference > Self.close {
                    off += 1
                    break
                }
            }
        }
        #expect(off == 0, "\(file): \(off) pixels of the rule's rows off")
    }

    private func compare(_ file: String, with rendered: [UInt8]) throws {
        let reference = try #require(Self.rgb(file), "missing or malformed \(file)")
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
