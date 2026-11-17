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
}
