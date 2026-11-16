// The menu-bar icon (#34). Its own file, so the app icon work (#66 item 7) changes only this and the asset catalog.
import AppKit
import ControllerBridgePresentation

/// The menu-bar icon: a generic template glyph that follows the menu bar's appearance, plus a small state mark that
/// is a shape, not a color (template images can't carry color). The words are in the accessibility label.
enum MenuBarIcon {
    static func image(_ state: IconState) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let symbol = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
            symbol.draw(in: NSRect(x: 0, y: (rect.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height))
            let dot = NSRect(x: rect.width - 6, y: 0, width: 6, height: 6)
            switch state {
            case .ok: break
            case .attention: NSBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75)).stroke()
            case .error: NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func accessibilityLabel(_ presentation: StatusPresentation) -> String {
        presentation.lights.map { "\($0.label) \($0.word)" }.joined(separator: ", ")
    }
}
