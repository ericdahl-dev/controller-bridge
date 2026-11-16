// The Syndicate-style theme (#34): named colors, fonts and the reusable views every window uses. The logic behind it
// (palette contrast, deck badges, status words) lives in ControllerBridgePresentation and is tested there.
import ControllerBridgePresentation
import CoreText
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

enum Theme {
    /// Registers the bundled fonts (Contents/Resources/Fonts) for this process. Called first thing at launch.
    static func registerFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
                print("Couldn't register \(file.lastPathComponent): \(String(describing: error?.takeRetainedValue()))")
            }
        }
    }

    static let background = Color(Palette.background)
    static let panel = Color(Palette.panel)
    static let button = Color(Palette.button)
    static let buttonRaised = Color(Palette.buttonRaised)
    static let hairline = Color(Palette.hairline)
    static let text = Color(Palette.text)
    static let caption = Color(Palette.caption)
    static let attention = Color(Palette.attention)
    static let error = Color(Palette.error)

    static let corner: CGFloat = 3

    /// Inter for UI text, with tabular figures so numbers don't jitter.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black: "Inter-Bold"
        case .semibold, .medium: "Inter-SemiBold"
        default: "Inter-Regular"
        }
        return Font.custom(name, size: size).monospacedDigit()
    }

    /// IBM Plex Mono for values: ports, BPM, deck numbers.
    static func data(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name = switch weight {
        case .semibold, .bold, .heavy, .black: "IBMPlexMono-SmBld"
        case .medium: "IBMPlexMono-Medm"
        default: "IBMPlexMono"
        }
        return Font.custom(name, size: size)
    }

    /// Small, bold, uppercase gray caption, as over Syndicate's REMAIN or QUANTIZE.
    static let captionFont = ui(10, .bold)
}

/// A deck number on its colored square.
struct DeckBadgeView: View {
    let deck: Int

    var body: some View {
        let badge = DeckBadge(deck: deck)
        Text("\(deck)")
            .font(Theme.data(15, .semibold))
            .foregroundStyle(Color(badge.digit))
            .frame(width: 26, height: 26)
            .background(Color(badge.fill), in: RoundedRectangle(cornerRadius: Theme.corner))
            .accessibilityLabel("Deck \(deck)")
    }
}

/// A gray uppercase caption over a larger value.
struct CaptionValue: View {
    let caption: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption.uppercased()).font(Theme.captionFont).foregroundStyle(Theme.caption)
            Text(value).font(Theme.data(15)).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A status light: a colored dot and a word. The word carries the meaning; the dot never stands alone.
struct StatusLightView: View {
    let light: StatusLight

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(light.label.uppercased()).font(Theme.captionFont).foregroundStyle(Theme.caption)
            HStack(spacing: 5) {
                Circle().fill(Color(light.tone.color)).frame(width: 7, height: 7)
                Text(light.word).font(Theme.ui(12, .bold)).foregroundStyle(Color(light.tone.color))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The bottom bar: small uppercase text, as in Syndicate's "NETWORK: MASTER | 124.00". Each light's dot and word take
/// its state color, as in the big lights; labels stay gray. Reads the same as `StatusPresentation.line`.
struct StatusLineView: View {
    let presentation: StatusPresentation
    let deck: Int

    var body: some View {
        styledLine
            .font(Theme.ui(10, .semibold))
            .foregroundStyle(Theme.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.background)
    }

    private var styledLine: Text {
        let separator = Text(" · ").foregroundStyle(Theme.caption)
        var line = Text("")
        for light in presentation.lights {
            line = line + Text("\(light.label) ").foregroundStyle(Theme.caption)
                + Text("● \(light.word)").foregroundStyle(Color(light.tone.color)) + separator
        }
        return line + Text("DECK [\(deck)]").foregroundStyle(Theme.caption)
    }
}

/// Syndicate's flat button: a slightly lighter gray, a hairline edge and a small radius.
struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(12, .bold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(configuration.isPressed ? Theme.buttonRaised : Theme.button,
                        in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
