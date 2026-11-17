// The Mac App Store screenshot frame (#29): a 2880×1800 canvas (16:10, Apple's largest Mac size) with a caption band
// across the top and the app's snapshot fitted below it. Downscaled once to 1440×900 for the smaller size.
import CoreGraphics

public enum AppStoreFrame {
    public static let canvas = CGSize(width: 2880, height: 1800)
    static let margin: CGFloat = 120
    static let captionHeight: CGFloat = 280

    /// Where the caption and the shot go, top-left origin. The shot keeps its shape: as large as fits the area below
    /// the caption inside the margins, centered there.
    public static func layout(shot size: CGSize) -> (caption: CGRect, shot: CGRect) {
        let caption = CGRect(x: margin, y: 0, width: canvas.width - 2 * margin, height: captionHeight)
        let area = CGRect(x: margin, y: captionHeight, width: canvas.width - 2 * margin,
                          height: canvas.height - captionHeight - margin)
        guard size.width > 0, size.height > 0 else { return (caption, area) }
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        let shot = CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        return (caption, shot)
    }
}

import CoreText
import Foundation

extension AppStoreFrame {
    /// The frame at 2880×1800 and, downscaled once from it, 1440×900: `ground` all round, `caption` centered in Geist
    /// SemiBold in the band, `shot` where the layout puts it. Flat RGB, no alpha. Nil if CoreGraphics can't draw.
    public static func images(shot: CGImage, caption: String, ground: CGColor, text: CGColor) -> (large: CGImage, small: CGImage)? {
        _ = JogDisplayRenderer.fontsRegistered
        guard let large = draw(size: canvas, { context in
            context.setFillColor(ground)
            context.fill(CGRect(origin: .zero, size: canvas))
            let layout = layout(shot: CGSize(width: shot.width, height: shot.height))
            context.interpolationQuality = .high
            // Top-left layout into CoreGraphics' bottom-left space.
            context.draw(shot, in: CGRect(x: layout.shot.minX, y: canvas.height - layout.shot.maxY,
                                          width: layout.shot.width, height: layout.shot.height))
            let font = CTFontCreateWithName("Geist-SemiBold" as CFString, 92, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: caption, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: text,
            ]))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let baseline = canvas.height - layout.caption.midY - (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
            context.textPosition = CGPoint(x: layout.caption.midX - width / 2, y: baseline)
            CTLineDraw(line, context)
        }) else { return nil }
        let half = CGSize(width: canvas.width / 2, height: canvas.height / 2)
        guard let small = draw(size: half, { context in
            context.interpolationQuality = .high
            context.draw(large, in: CGRect(origin: .zero, size: half))
        }) else { return nil }
        return (large, small)
    }

    /// An sRGB bitmap with no alpha channel, drawn by `body`.
    private static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        body(context)
        return context.makeImage()
    }
}

extension AppStoreFrame {
    /// The shot's background: the sRGB color of its top-left pixel, where every snapshot shows only its ground.
    public static func ground(of shot: CGImage) -> CGColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // The 1×1 context shows the shot's top-left pixel: the shot drawn with that pixel at its origin.
        context.interpolationQuality = .none
        context.draw(shot, in: CGRect(x: 0, y: -CGFloat(shot.height) + 1, width: CGFloat(shot.width), height: CGFloat(shot.height)))
        return CGColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}
