import CoreGraphics
@testable import ControllerBridgeRender
import Testing

/// The Mac App Store screenshot frame (#29): 2880×1800, a caption band across the top, and the shot fitted below it
/// inside 120 px margins, centered, never stretched out of its shape. Worked by hand: the shot area is x 120…2760,
/// y 280…1680 (2640×1400).
@Suite("App Store frame layout")
struct AppStoreFrameTests {
    @Test("A shot of the area's own shape fills it: 1320×700 at 2x is 120, 280, 2640×1400")
    func sameShape() {
        let layout = AppStoreFrame.layout(shot: CGSize(width: 1320, height: 700))
        #expect(layout.shot == CGRect(x: 120, y: 280, width: 2640, height: 1400))
        #expect(layout.caption == CGRect(x: 120, y: 0, width: 2640, height: 280))
    }

    @Test("A tall panel (720×1056) fits the height, 1400, and is centered: width 954.5…, x 962.7…")
    func tall() {
        let shot = AppStoreFrame.layout(shot: CGSize(width: 720, height: 1056)).shot
        #expect(abs(shot.height - 1400) < 0.001)
        #expect(abs(shot.width - 720 * 1400 / 1056.0) < 0.001)
        #expect(abs(shot.minX - (1440 - 720 * 1400 / 1056.0 / 2)) < 0.001)
        #expect(shot.minY == 280)
    }

    @Test("A wide shot (2000×800, wider than the area) fits the width: 120, 452, 2640×1056")
    func wide() {
        let shot = AppStoreFrame.layout(shot: CGSize(width: 2000, height: 800)).shot
        #expect(shot == CGRect(x: 120, y: 452, width: 2640, height: 1056))
    }
}
