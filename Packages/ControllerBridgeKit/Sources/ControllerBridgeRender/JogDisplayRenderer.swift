// The LC6000 jog display's image (#165): 198×198, round, upright, in the chosen design B, "track first". From the top:
// the deck as a chip in its color and a player badge; the title (the biggest text, one line, or two split at a word);
// the artist; a rule in the deck color; key and BPM. Around the edge, the master clock's four beat sections. A value
// Syndicate didn't send shows "—", never a made-up one. Every line is cut with an ellipsis to the round screen, never
// shrunk: nothing is under 14 px. The layout is the designer's (gen.py), in its pixels.
//
// A pure function, shared by the upload and the Diagnostics simulator (#221). The upload draws no lit beat and no
// marker: the marker is the unit's own (pitch bend), and a lit beat would need an upload per beat. The simulator can
// pass both to show what the unit would.
import ControllerBridgeCore
import CoreGraphics
import CoreText
import Foundation

public enum JogDisplayRenderer {
    public static let size = JogImage.size

    /// RGBA bytes, row by row, top first, upright: what `JogImage.forUnit` turns and encodes. `litBeat` (1–4) lights
    /// that beat's section; `marker` draws the marker that many turns clockwise from 12 o'clock.
    public static func render(_ content: JogDisplayContent, litBeat: Int? = nil, marker: Double? = nil) -> [UInt8] {
        _ = fontsRegistered
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixels }
        // Top-left origin, y down, as the rows are stored and as the design measures.
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        draw(content, litBeat: litBeat, in: context)
        if let marker { drawMarker(turns: marker, in: context) }
        return pixels
    }

    // MARK: The design's measurements

    static let center: CGFloat = 99
    static let ringOuter: CGFloat = 95, ringInner: CGFloat = 85
    /// The gap between beat sections, measured at mid-band.
    static let ringGap: CGFloat = 7
    /// Text stays inside this circle, 6 px clear of the ring.
    static let safe: CGFloat = 79

    static let background = rgb(0x0B0B0B), text = rgb(0xEDEDEA), caption = rgb(0xBDBDBD), keyColor = rgb(0x9DC3EE)
    static let live = rgb(0x00FF48), beatOff = rgb(0x2C2C2C), downbeatOff = rgb(0x5A5A5A)

    /// The badge for Syndicate's player type: TRK for a track, OSC, MIDI or SEQ for a clip of that kind (#209).
    static func badge(_ playerType: String?) -> String? {
        guard let type = playerType?.lowercased(), !type.isEmpty, type != "empty" else { return nil }
        if type == "track" { return "TRK" }
        for (needle, label) in [("osc", "OSC"), ("midi", "MIDI"), ("seq", "SEQ")] where type.contains(needle) { return label }
        return String(type.uppercased().prefix(4))
    }

    // MARK: Drawing

    /// The Geist faces the design uses, bundled with this target (#221) so the image is the same in the app and under
    /// `swift test`: unregistered, CoreText would quietly draw another font. Registered once, for this process.
    static let fontNames = ["Geist-Bold", "Geist-Medium", "GeistMono-SemiBold"]
    private static let fontsRegistered: Void = {
        let urls = fontNames.compactMap { Bundle.module.url(forResource: $0, withExtension: "ttf", subdirectory: "Fonts") }
        // Already registered (the app registers its own copies) is fine: the same faces either way.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()

    private static func draw(_ content: JogDisplayContent, litBeat: Int?, in context: CGContext) {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: 198, height: 198))
        ring(litBeat: litBeat, in: context)
        let deckColor = color(content.color)
        header(deck: content.deck, color: deckColor, badge: badge(content.playerType), in: context)

        let title = content.title ?? ""
        let foot: Bool
        if title.isEmpty {
            // No title: an OSC clip (or another clip) says what it is; an empty deck says so. Nothing invented.
            let isClip = badge(content.playerType).map { $0 != "TRK" } ?? false
            line(isClip ? "OSC clip" : "No track", font: "Geist-Bold", size: 26, lineHeight: 1.1, top: 66, color: text, in: context)
            line(isClip ? "no title" : "Load a track", font: "Geist-Medium", size: 16, lineHeight: 1.1, top: 100,
                 color: caption, in: context)
            foot = isClip
        } else {
            let artistTop: CGFloat
            if title.count <= 12 {
                line(title, font: "Geist-Bold", size: 26, lineHeight: 1.15, top: 60, color: text, tracking: -0.01, in: context)
                artistTop = 94
            } else {
                let (first, second) = split(title)
                line(first, font: "Geist-Bold", size: 22, lineHeight: 1.1, top: 54, color: text, in: context)
                line(second, font: "Geist-Bold", size: 22, lineHeight: 1.1, top: 78, color: text, in: context)
                artistTop = 103
            }
            line(content.artist.flatMap { $0.isEmpty ? nil : $0 } ?? "—", font: "Geist-Medium", size: 16, lineHeight: 1.15,
                 top: artistTop, color: caption, in: context)
            foot = true
        }
        // The rule in the deck color.
        context.setFillColor(deckColor)
        context.fill(CGRect(x: 50, y: 127, width: 98, height: 2))
        if foot { keyAndBPM(key: content.key, bpm: content.bpm, in: context) }
    }

    /// The four beat sections, clockwise from 12 o'clock; beat 1 a step brighter when unlit.
    private static func ring(litBeat: Int?, in context: CGContext) {
        let half = (ringGap / ((ringOuter + ringInner) / 2)) / 2
        for beat in 0..<4 {
            let start = CGFloat(beat) * .pi / 2 + half, end = CGFloat(beat + 1) * .pi / 2 - half
            let path = CGMutablePath()
            // Angles from 12 o'clock clockwise; on screen (y down) that's CoreGraphics angle − π/2, growing clockwise.
            path.addArc(center: CGPoint(x: center, y: center), radius: ringOuter, startAngle: start - .pi / 2,
                        endAngle: end - .pi / 2, clockwise: false)
            path.addArc(center: CGPoint(x: center, y: center), radius: ringInner, startAngle: end - .pi / 2,
                        endAngle: start - .pi / 2, clockwise: true)
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(litBeat == beat + 1 ? live : beat == 0 ? downbeatOff : beatOff)
            context.fillPath()
        }
    }

    /// The deck chip (a 26 px circle in the deck color, its number in black) and the player badge, centered at y 37.
    private static func header(deck: Int, color deckColor: CGColor, badge label: String?, in context: CGContext) {
        let chip: CGFloat = 26, gap: CGFloat = 6, mid: CGFloat = 37
        let badgeFont = CTFontCreateWithName("GeistMono-SemiBold" as CFString, 14, nil)
        let badgeLine = label.map { makeLine($0, font: badgeFont, color: text, tracking: 0.04) }
        let badgeWidth = badgeLine.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) + 12 + 3 } ?? 0
        let total = chip + (badgeLine == nil ? 0 : gap + badgeWidth)
        let left = center - total / 2
        context.setFillColor(deckColor)
        context.fillEllipse(in: CGRect(x: left, y: mid - chip / 2, width: chip, height: chip))
        let number = CTFontCreateWithName("Geist-Bold" as CFString, 18, nil)
        draw(makeLine("\(deck)", font: number, color: background), font: number, centerX: left + chip / 2, centerY: mid,
             in: context)
        guard let badgeLine else { return }
        // A 1.5 px outline, 5 px corners, 22 px tall.
        let box = CGRect(x: left + chip + gap, y: mid - 11, width: badgeWidth, height: 22).insetBy(dx: 0.75, dy: 0.75)
        context.setStrokeColor(caption)
        context.setLineWidth(1.5)
        context.addPath(CGPath(roundedRect: box, cornerWidth: 4.25, cornerHeight: 4.25, transform: nil))
        context.strokePath()
        draw(badgeLine, font: badgeFont, centerX: box.midX, centerY: mid + 0.5, in: context)
    }

    /// Key in blue and BPM in white, monospaced, at y 136; "—" for either one Syndicate didn't send.
    private static func keyAndBPM(key: String?, bpm: Double?, in context: CGContext) {
        let font = CTFontCreateWithName("GeistMono-SemiBold" as CFString, 22, nil)
        let keyText = key.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let bpmText = bpm.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil } ?? "—"
        let string = NSMutableAttributedString(string: keyText + " " + bpmText, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: text,
        ])
        string.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: keyColor,
                            range: NSRange(location: 0, length: (keyText as NSString).length))
        // Not cut to the safe circle, as in the design: a key and a BPM are short, and both must show whole.
        let height = lineBoxHeight(font, lineHeight: nil)
        draw(CTLineCreateWithAttributedString(string), font: font, centerX: center, centerY: 136 + height / 2, in: context)
    }

    /// The marker: a white wedge with a black keyline riding the ring's edge, pointing in.
    private static func drawMarker(turns: Double, in context: CGContext) {
        let degrees = turns.truncatingRemainder(dividingBy: 1) * 360
        func point(_ radius: CGFloat, _ deg: Double) -> CGPoint {
            let a: Double = deg * Double.pi / 180
            let x: CGFloat = center + radius * CGFloat(sin(a))
            let y: CGFloat = center - radius * CGFloat(cos(a))
            return CGPoint(x: x, y: y)
        }
        let path = CGMutablePath()
        path.addLines(between: [point(ringInner - 6, degrees), point(98.5, degrees - 4.2), point(98.5, degrees + 4.2)])
        path.closeSubpath()
        context.setLineJoin(.round)
        context.setLineWidth(2)
        context.setStrokeColor(rgb(0x000000))
        context.addPath(path)
        context.strokePath()
        context.setFillColor(rgb(0xFFFFFF))
        context.addPath(path)
        context.fillPath()
    }

    // MARK: Text

    /// The title split at the word break nearest its middle, as the design does.
    static func split(_ title: String) -> (String, String) {
        let words = title.split(separator: " ").map(String.init)
        guard words.count > 1 else { return (title, "") }
        let half = Double(title.count) / 2
        func offMiddle(_ cut: Int) -> Double { abs(Double(words[..<cut].joined(separator: " ").count) - half) }
        let best = (1..<words.count).min { offMiddle($0) < offMiddle($1) }!
        return (words[..<best].joined(separator: " "), words[best...].joined(separator: " "))
    }

    /// One centered line whose CSS line box starts at `top`, cut with an ellipsis to the safe circle's chord there.
    private static func line(_ string: String, font name: String, size: CGFloat, lineHeight: CGFloat, top: CGFloat,
                             color: CGColor, tracking: CGFloat = 0, in context: CGContext) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let height = lineBoxHeight(font, lineHeight: lineHeight)
        let fitted = fit(makeLine(string, font: font, color: color, tracking: tracking), font: font, top: top, height: height)
        draw(fitted, font: font, centerX: center, centerY: top + height / 2, in: context)
    }

    /// A CSS line box's height: `lineHeight` × the size, or the font's own ascent + descent + leading for "normal".
    private static func lineBoxHeight(_ font: CTFont, lineHeight: CGFloat?) -> CGFloat {
        if let lineHeight { return lineHeight * CTFontGetSize(font) }
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// The line cut with an ellipsis to the width of the safe circle at the box's farther edge from the center.
    private static func fit(_ line: CTLine, font: CTFont, top: CGFloat, height: CGFloat) -> CTLine {
        let dy = max(abs(top - center), abs(top + height - center))
        let width = 2 * sqrt(max(0, safe * safe - dy * dy))
        guard CTLineGetTypographicBounds(line, nil, nil, nil) > width else { return line }
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let attributes = runs.first.map { CTRunGetAttributes($0) as! [NSAttributedString.Key: Any] } ?? [:]
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line
    }

    private static func makeLine(_ string: String, font: CTFont, color: CGColor, tracking: CGFloat = 0) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            kCTKernAttributeName as NSAttributedString.Key: tracking * CTFontGetSize(font),
        ]))
    }

    /// Draws a line centered on (centerX, centerY) the way CSS centers text in its line box: the baseline at
    /// centerY + (ascent − descent) / 2.
    private static func draw(_ line: CTLine, font: CTFont, centerX: CGFloat, centerY: CGFloat, in context: CGContext) {
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let baseline = centerY + (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
        context.saveGState()
        context.textMatrix = .identity
        // CoreText draws y up: flip around the baseline.
        context.translateBy(x: centerX - width / 2, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Colors

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    private static func color(_ rgb: [Int]) -> CGColor {
        guard rgb.count == 3 else { return text }
        return CGColor(srgbRed: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1)
    }
}
