import ControllerBridgeCore
@testable import ControllerBridgeRender
import CoreText
import Testing

@Suite("Jog display renderer")
struct JogDisplayRendererTests {
    @Test("A 198×198 RGBA image, 4 bytes a pixel")
    func size() {
        #expect(JogDisplayRenderer.render(JogDisplayContent(deck: 1, color: [255, 0, 0])).count == 198 * 198 * 4)
    }

    @Test("Each face the design uses is the real Geist, not a fallback, under swift test too", arguments: ["Geist-Bold", "Geist-Medium", "GeistMono-SemiBold"])
    func realFonts(name: String) {
        _ = JogDisplayRenderer.render(JogDisplayContent(deck: 1, color: [255, 0, 0]))   // registers the faces
        #expect(CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 16, nil)) as String == name)
        #expect(JogDisplayRenderer.fontNames.contains(name))
    }

    static let contents = [
        JogDisplayContent(deck: 1, color: [255, 0, 0]),
        JogDisplayContent(deck: 2, color: [255, 255, 0], title: "Daybreak", artist: "Night Drive", key: "A#m", bpm: 128,
                          playerType: "track"),
        JogDisplayContent(deck: 3, color: [0, 255, 255], playerType: "osc"),
    ]

    @Test("The simulator, with no lit beat or marker, shows exactly the image prepared for the upload, before its turn")
    func simulatorIsTheUpload() {
        for content in Self.contents {
            #expect(JogDisplayRenderer.simulatorImage(content, litBeat: nil, marker: nil) == JogDisplayRenderer.uploadImage(content))
        }
    }

    @Test("The simulator's lit beat and marker draw over that image: with them it differs, so they really show")
    func simulatorOverlays() {
        let content = Self.contents[1]
        #expect(JogDisplayRenderer.simulatorImage(content, litBeat: 2, marker: nil) != JogDisplayRenderer.uploadImage(content))
        #expect(JogDisplayRenderer.simulatorImage(content, litBeat: nil, marker: 0.25) != JogDisplayRenderer.uploadImage(content))
    }

    @Test("Each beat slot's upload (#215) is the simulator's image for that beat, without the marker; the four differ")
    func beatSlotsMatchTheSimulator() {
        let content = Self.contents[1]
        let images = (1...4).map { JogDisplayRenderer.uploadImage(content, litBeat: $0) }
        for beat in 1...4 {
            #expect(images[beat - 1] == JogDisplayRenderer.simulatorImage(content, litBeat: beat, marker: nil))
        }
        #expect(Set(images).count == 4)
    }

    /// The waiting look (#464): our logo (design/icon/icon-1-deck-ring.svg, its deck ring without the tile) centered at
    /// 0.24 scale, the beat ring all dark, and nothing of the deck. Points are the SVG's, scaled: arcs at radius 62.9
    /// (262 × 0.24), the inner disc to 49.4, the hub 17.8 with a 6.2 hole; the arcs leave a gap on each axis.
    @Test("Stale feedback draws our logo, the beat ring dark and nothing of the deck")
    func staleDrawsTheLogo() {
        let image = JogDisplayRenderer.render(JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Daybreak",
                                                                artist: "Night Drive", key: "A#m", bpm: 128,
                                                                playerType: "track", stale: true))
        func at(_ x: Int, _ y: Int) -> [UInt8] { Self.pixel(image, x: x, y: y) }
        #expect(at(99, 99) == [0x14, 0x14, 0x15, 255])     // the hub's hole
        #expect(at(99, 111) == [0xD5, 0xD5, 0xD5, 255])    // the hub
        #expect(at(99, 135) == [0x1D, 0x1D, 0x1E, 255])    // the inner disc
        #expect(at(143, 55) == [0x6C, 0x72, 0x77, 255])    // the arcs, clockwise from the top right
        #expect(at(143, 143) == [0xEC, 0xCF, 0x65, 255])
        #expect(at(55, 143) == [0xC5, 0x75, 0x4E, 255])
        #expect(at(55, 55) == [0x62, 0x92, 0x9E, 255])
        #expect(at(99, 154) == [0x0B, 0x0B, 0x0B, 255])    // the gap below: no key or BPM
        #expect(at(99, 37) == [0x0B, 0x0B, 0x0B, 255])     // the gap above: no deck chip
        #expect(at(163, 35) == [0x2C, 0x2C, 0x2C, 255])    // beat 1's section, dark like the others
    }

    /// One pixel of a 198×198 RGBA image, upright: [r, g, b, a].
    static func pixel(_ rgba: [UInt8], x: Int, y: Int) -> [UInt8] { Array(rgba[(y * 198 + x) * 4..<(y * 198 + x) * 4 + 4]) }

    /// The level meter (#461), the user's pick: a thin arc just inside the beat ring on the left, r 80–83, from 240° to
    /// 300° clockwise from 12 o'clock, filling bottom-up. Points sit mid-band (r 81.5): (24, 132) at a tenth of the
    /// arc, (17, 98) at half, (24, 65) at nine tenths, (19, 81) at peak 90's place (282.5°).
    static func meterImage(level: Int, peak: Int, stale: Bool = false) -> [UInt8] {
        JogDisplayRenderer.simulatorImage(JogDisplayContent(deck: 4, color: [0, 128, 255], stale: stale), litBeat: nil,
                                          marker: nil, meter: (level: level, peak: peak))
    }

    static func near(_ pixel: [UInt8], _ rgb: UInt32, by tolerance: Int = 24) -> Bool {
        let want = [Int(rgb >> 16 & 0xFF), Int(rgb >> 8 & 0xFF), Int(rgb & 0xFF)]
        return zip(pixel.prefix(3), want).allSatisfy { abs(Int($0) - $1) <= tolerance }
    }

    @Test("Silence: the meter's track shows dark, nothing lit")
    func meterAtSilence() {
        let image = Self.meterImage(level: 0, peak: 0)
        for (x, y) in [(24, 132), (17, 98), (24, 65)] { #expect(Self.near(Self.pixel(image, x: x, y: y), 0x2C2C2C)) }
    }

    @Test("Mid level fills green from the bottom; the held peak is a white tick above it")
    func meterAtMid() {
        let image = Self.meterImage(level: 64, peak: 90)
        #expect(Self.near(Self.pixel(image, x: 24, y: 132), 0x00FF48))
        #expect(Self.near(Self.pixel(image, x: 24, y: 65), 0x2C2C2C))
        #expect(Self.near(Self.pixel(image, x: 19, y: 81), 0xFFFFFF, by: 60))
    }

    @Test("Near the top the fill turns yellow; the bottom stays green")
    func meterNearTheTop() {
        let image = Self.meterImage(level: 120, peak: 120)
        #expect(Self.near(Self.pixel(image, x: 24, y: 132), 0x00FF48))
        #expect(Self.near(Self.pixel(image, x: 24, y: 65), 0xFFD400))
    }

    @Test("At clip the whole fill is red")
    func meterAtClip() {
        let image = Self.meterImage(level: 127, peak: 127)
        for (x, y) in [(24, 132), (17, 98), (24, 65)] { #expect(Self.near(Self.pixel(image, x: x, y: y), 0xFF3B30)) }
    }

    @Test("Stale draws no meter")
    func meterNotWhenStale() {
        #expect(Self.near(Self.pixel(Self.meterImage(level: 64, peak: 90, stale: true), x: 17, y: 98), 0x0B0B0B))
    }

}
