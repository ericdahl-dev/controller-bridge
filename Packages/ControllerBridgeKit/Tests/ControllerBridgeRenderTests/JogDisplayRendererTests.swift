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
}
