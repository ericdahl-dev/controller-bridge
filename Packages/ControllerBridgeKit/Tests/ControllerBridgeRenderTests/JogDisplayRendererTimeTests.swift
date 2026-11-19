import ControllerBridgeCore
@testable import ControllerBridgeRender
import Testing

/// Track time on the drawn display (#460), the user's pick: the remaining time alone ("-2:45"), about 18 px, in the
/// slot under key/BPM; a 2 px progress ring just outside the beat ring (r 96–98), filling clockwise from 12. An
/// unknown length (0) draws neither.
@Suite("Jog display renderer: track time")
struct JogDisplayRendererTimeTests {
    static let content = JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Daybreak", artist: "Night Drive",
                                           key: "A#m", bpm: 128, playerType: "track")

    static func image(_ time: (elapsed: Int, length: Int)?) -> [UInt8] {
        JogDisplayRenderer.simulatorImage(content, litBeat: nil, marker: nil, time: time)
    }

    /// The pixels (x, y) where two images differ.
    static func changed(_ a: [UInt8], _ b: [UInt8]) -> [(x: Int, y: Int)] {
        (0..<198 * 198).compactMap { i in a[i * 4..<i * 4 + 3] == b[i * 4..<i * 4 + 3] ? nil : (i % 198, i / 198) }
    }

    static func radius(_ p: (x: Int, y: Int)) -> Double {
        let dx = Double(p.x) + 0.5 - 99, dy = Double(p.y) + 0.5 - 99
        return (dx * dx + dy * dy).squareRoot()
    }

    @Test("No time, or an unknown length, draws nothing of it")
    func nothingWithoutLength() {
        let plain = JogDisplayRenderer.simulatorImage(Self.content, litBeat: nil, marker: nil)
        #expect(Self.image(nil) == plain)
        #expect(Self.image((elapsed: 42, length: 0)) == plain)
    }

    /// "-99:59" is the widest a track under 100 minutes shows.
    @Test("The remaining time draws below key/BPM, inside the text-safe circle, centred", arguments: [
        (elapsed: 0, length: 165), (elapsed: 600, length: 4365), (elapsed: 0, length: 5999),
    ])
    func remainingFits(elapsed: Int, length: Int) {
        let inside = Self.changed(Self.image(nil), Self.image((elapsed, length))).filter { Self.radius($0) < 90 }
        #expect(!inside.isEmpty)
        // Below key/BPM's ink (its last row is y 159), a gap between, and inside the text-safe circle (r 79).
        #expect(inside.allSatisfy { $0.y >= 162 })
        #expect(inside.allSatisfy { Self.radius($0) <= JogDisplayRenderer.safe })
        let xs = inside.map(\.x)
        #expect(abs((xs.min()! + xs.max()!) / 2 - 99) <= 2)
    }

    @Test("Different remaining times draw differently; past the end shows no less than -0:00")
    func remainingTracksTime() {
        #expect(Self.image((elapsed: 0, length: 165)) != Self.image((elapsed: 1, length: 165)))
        #expect(Self.image((elapsed: 200, length: 165)) == Self.image((elapsed: 165, length: 165)))
    }
}
