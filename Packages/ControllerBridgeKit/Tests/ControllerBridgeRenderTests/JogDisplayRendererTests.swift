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

    /// One pixel of a 198×198 RGBA image, upright: [r, g, b, a].
    static func pixel(_ rgba: [UInt8], x: Int, y: Int) -> [UInt8] { Array(rgba[(y * 198 + x) * 4..<(y * 198 + x) * 4 + 4]) }

    @Test("The loading graphic (#165, slot 5) is design B's ground and unlit ring with no deck info, and the word in the middle")
    func loadingImage() {
        let loading = JogDisplayRenderer.loadingImage()
        let card = JogDisplayRenderer.uploadImage(Self.contents[1])
        #expect(loading.count == 198 * 198 * 4)
        // The ground: a corner, and just inside the ring, are the card's.
        #expect(Self.pixel(loading, x: 2, y: 2) == Self.pixel(card, x: 2, y: 2))
        #expect(Self.pixel(loading, x: 99, y: 18) == Self.pixel(card, x: 2, y: 2))
        // The ring: the middle of each quarter (radius 90, at 45°, 135°, 225° and 315°) is the card's, unlit.
        for (x, y) in [(163, 35), (163, 163), (35, 163), (35, 35)] {
            #expect(Self.pixel(loading, x: x, y: y) == Self.pixel(card, x: x, y: y), "\(x),\(y)")
        }
        // No deck info: where the card has its deck-color rule, the loading graphic has ground.
        #expect(Self.pixel(card, x: 99, y: 128) != Self.pixel(card, x: 2, y: 2))
        #expect(Self.pixel(loading, x: 99, y: 128) == Self.pixel(card, x: 2, y: 2))
        // The word: some pixels across the middle row are drawn in the text color, not ground.
        let ground = Self.pixel(card, x: 2, y: 2)
        #expect((60...138).contains { Self.pixel(loading, x: $0, y: 99) != ground })
        #expect(loading != card)
    }
}
