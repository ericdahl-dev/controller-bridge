// The LC6000 jog display's image (#165): 198×198, round, upright. The outer ring is the master clock's four beat
// sections (the marker is the hand that moves over them); inside, the deck in front: its number in its deck color,
// the track's title and artist, its key and BPM, and a badge when the player isn't a plain track. Redrawn only when
// the content changes. A pure function, shared by the upload and the Diagnostics simulator (#221).
import ControllerBridgeCore
import CoreGraphics
import CoreText
import Foundation

enum JogDisplayRenderer {
    static let size = JogImage.size

    /// RGBA bytes, row by row, top first, upright: what `JogImage.forUnit` turns and encodes.
    static func render(_ content: JogDisplayContent) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixels }
        // Top-left origin, as the rows are stored.
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        draw(content, in: context)
        return pixels
    }

    private static func draw(_ content: JogDisplayContent, in context: CGContext) {
        let side = CGFloat(size), center = CGPoint(x: side / 2, y: side / 2)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let deckColor = color(content.color)
        ring(in: context, center: center, radius: side / 2 - 8, color: deckColor)
        let hasTrack = !(content.title ?? "").isEmpty
        text("\(content.deck)", font: "Geist-SemiBold", size: 40, color: deckColor, centerX: center.x, top: 30, width: 120,
             in: context)
        if hasTrack {
            text(content.title ?? "", font: "Geist-Medium", size: 15, color: white, centerX: center.x, top: 80, width: 132, in: context)
            text(content.artist ?? "", font: "Geist-Regular", size: 12, color: gray, centerX: center.x, top: 100, width: 124,
                 in: context)
            let bpm = content.bpm.map { String(format: "%.1f", $0) } ?? ""
            let line = [content.key ?? "", bpm].filter { !$0.isEmpty }.joined(separator: " · ")
            text(line, font: "GeistMono-Medium", size: 13, color: white, centerX: center.x, top: 124, width: 120, in: context)
            if let type = content.playerType, !type.isEmpty, type != "track" {
                text(type.uppercased(), font: "GeistMono-Medium", size: 10, color: deckColor, centerX: center.x, top: 146,
                     width: 80, in: context)
            }
        } else {
            text("No track", font: "Geist-Regular", size: 13, color: gray, centerX: center.x, top: 92, width: 120, in: context)
        }
    }

    /// The master clock's four beat sections around the edge, a small gap between each, starting at 12 o'clock.
    private static func ring(in context: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
        context.setLineWidth(9)
        context.setLineCap(.butt)
        context.setStrokeColor(color.copy(alpha: 0.55) ?? color)
        let gap = CGFloat.pi / 60
        for beat in 0..<4 {
            // Clockwise from 12 o'clock on screen (y down): angles grow clockwise.
            let start = -CGFloat.pi / 2 + CGFloat(beat) * .pi / 2 + gap
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .pi / 2 - 2 * gap, clockwise: false)
            context.strokePath()
        }
    }

    private static let white = CGColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1)
    private static let gray = CGColor(srgbRed: 0.66, green: 0.66, blue: 0.65, alpha: 1)

    private static func color(_ rgb: [Int]) -> CGColor {
        guard rgb.count == 3 else { return white }
        return CGColor(srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1)
    }

    /// One line, centered, cut with an ellipsis to `width`.
    private static func text(_ string: String, font name: String, size: CGFloat, color: CGColor, centerX: CGFloat, top: CGFloat,
                             width: CGFloat, in context: CGContext) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let line = CTLineCreateTruncatedLine(full, Double(width), .end, ellipsis) ?? full
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.saveGState()
        // CoreText draws with y up: flip back around the line's baseline.
        context.textMatrix = .identity
        context.translateBy(x: centerX - bounds.width / 2 - bounds.minX, y: top + size)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
