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
}
