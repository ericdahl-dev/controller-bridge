import ControllerBridgePresentation
import Testing

/// Expected ratios are worked from the WCAG 2.x definition: (L1 + 0.05) / (L2 + 0.05) with sRGB relative luminance.
@Suite("Contrast")
struct ContrastTests {
    @Test("White on black is the maximum, 21:1")
    func whiteOnBlack() {
        #expect(Contrast.ratio(RGB(hex: 0xFFFFFF), RGB(hex: 0x000000)) == 21)
    }

    // #777777: channel 119/255 = 0.46667 → ((0.46667 + 0.055) / 1.055)^2.4 = 0.18447. Against white:
    // (1.05) / (0.18447 + 0.05) = 4.478. The well-known "just fails AA" gray.
    @Test("#777777 on white is 4.48:1, either way round")
    func midGrayOnWhite() {
        #expect(abs(Contrast.ratio(RGB(hex: 0x777777), RGB(hex: 0xFFFFFF)) - 4.478) < 0.001)
        #expect(abs(Contrast.ratio(RGB(hex: 0xFFFFFF), RGB(hex: 0x777777)) - 4.478) < 0.001)
    }
}
