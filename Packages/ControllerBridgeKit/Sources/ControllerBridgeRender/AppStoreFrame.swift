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
