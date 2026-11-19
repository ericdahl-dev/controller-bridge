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

    static func at(_ image: [UInt8], _ x: Int, _ y: Int) -> [UInt8] { JogDisplayRendererTests.pixel(image, x: x, y: y) }

    /// The progress ring (r 96–98): filled in the deck colour clockwise from 12, the rest a dark track. Points mid-band
    /// (r ≈ 97): (115, 3) at 10°, (196, 98) at 90°, (98, 196) at 180°, (1, 98) at 270°.
    @Test("Halfway: the ring is lit in the deck colour to 6 o'clock, dark after")
    func progressHalfway() {
        let image = Self.image((elapsed: 60, length: 120))
        #expect(JogDisplayRendererTests.near(Self.at(image, 115, 3), 0xFF0000))
        #expect(JogDisplayRendererTests.near(Self.at(image, 196, 98), 0xFF0000))
        #expect(JogDisplayRendererTests.near(Self.at(image, 1, 98), 0x2C2C2C))
    }

    @Test("At the start the whole ring is the dark track; at the end it is all lit")
    func progressEnds() {
        let start = Self.image((elapsed: 0, length: 120)), end = Self.image((elapsed: 120, length: 120))
        for (x, y) in [(115, 3), (196, 98), (98, 196), (1, 98)] {
            #expect(JogDisplayRendererTests.near(Self.at(start, x, y), 0x2C2C2C))
            #expect(JogDisplayRendererTests.near(Self.at(end, x, y), 0xFF0000))
        }
    }

    @Test("The ring stays in its band, clear of the beat ring (r 95) and inside the image's edge")
    func progressBand() {
        let ring = Self.changed(Self.image(nil), Self.image((elapsed: 60, length: 120))).filter { Self.radius($0) >= 90 }
        #expect(!ring.isEmpty)
        #expect(ring.allSatisfy { Self.radius($0) > 95 && Self.radius($0) < 99 })
    }

    static func slot(_ image: [UInt8]) -> [[UInt8]] {
        (163...175).flatMap { y in (60...138).map { x in Self.at(image, x, y) } }
    }

    @Test("The warning's red half: the remaining time and the ring's fill turn red (0xFF3B30); the track stays dark")
    func warningRed() {
        let image = JogDisplayRenderer.simulatorImage(Self.content, litBeat: nil, marker: nil,
                                                      time: (elapsed: 90, length: 120), warning: true)
        #expect(JogDisplayRendererTests.near(Self.at(image, 196, 98), 0xFF3B30, by: 8))
        #expect(JogDisplayRendererTests.near(Self.at(image, 1, 98), 0x2C2C2C))
        #expect(Self.slot(image).contains { JogDisplayRendererTests.near($0, 0xFF3B30, by: 8) })
        #expect(!Self.slot(image).contains { JogDisplayRendererTests.near($0, 0xEDEDEA, by: 8) })
    }

    @Test("Without the warning the remaining time is white and the fill the deck colour")
    func warningOff() {
        let image = Self.image((elapsed: 90, length: 120))
        #expect(Self.slot(image).contains { JogDisplayRendererTests.near($0, 0xEDEDEA, by: 8) })
        #expect(!Self.slot(image).contains { JogDisplayRendererTests.near($0, 0xFF3B30, by: 8) })
    }
}
