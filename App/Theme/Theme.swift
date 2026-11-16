// The Syndicate-style theme (#34): named colors, fonts and the reusable views every window uses. The logic behind it
// (palette contrast, deck badges, status words) lives in ControllerBridgePresentation and is tested there.
import ControllerBridgeCore
import ControllerBridgePresentation
import CoreText
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    /// A theme color that follows the effective appearance: Syndicate's dark value or its light one (#127).
    init(_ token: KeyPath<ThemePalette, RGB>) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
            return NSColor(Palette.themed(dark: dark)[keyPath: token])
        })
    }

    /// A status tone's color in the effective appearance.
    init(tone: StatusLight.Tone) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
            return NSColor(tone.color(in: Palette.themed(dark: dark)))
        })
    }
}

extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

extension Palette {
    static func themed(dark: Bool) -> ThemePalette { dark ? Palette.dark : Palette.light }
}

extension Appearance {
    /// The app's look for this setting: nil follows macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .matchMacOS: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
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

    // Syndicate's tokens, dark or light with the appearance (#127).
    static let background = Color(\.background)
    static let panel = Color(\.panel)
    static let button = Color(\.button)
    static let buttonRaised = Color(\.buttonRaised)
    static let hairline = Color(\.hairline)
    static let text = Color(\.text)
    static let caption = Color(\.caption)
    static let attention = Color(\.attention)
    static let error = Color(\.error)
    static let live = Color(\.live)

    static let corner: CGFloat = 3

    /// Spacing steps. Use these, not one-off numbers, so every window keeps one rhythm.
    enum Space {
        static let xs: CGFloat = 3
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
    }

    /// Type sizes, smallest first.
    enum Size {
        static let caption: CGFloat = 10
        static let body: CGFloat = 11
        static let label: CGFloat = 12
        static let emphasis: CGFloat = 13
        static let title: CGFloat = 14
        static let value: CGFloat = 15
        static let heading: CGFloat = 18
    }

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
    static let captionFont = ui(Size.caption, .bold)
}

/// A deck number on its colored square.
struct DeckBadgeView: View {
    let deck: Int
    /// The deck colors in use (#123): Syndicate's palette, the user's, or the defaults.
    @Environment(\.deckColors) private var colors

    var body: some View {
        let badge = colors[deck].map { DeckBadge(fill: RGB(deckColor: $0)) } ?? DeckBadge(deck: deck)
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
            // Natural case in, uppercase on screen: VoiceOver reads words, not letters (#67).
            Text(caption).textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
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
            Text(light.label).textCase(.uppercase).font(Theme.captionFont).foregroundStyle(Theme.caption)
            HStack(spacing: 5) {
                Circle().fill(Color(tone: light.tone)).frame(width: 7, height: 7)
                // A word never breaks mid-word; the panel lays lights out in a grid instead.
                Text(light.word).textCase(.uppercase).font(Theme.ui(12, .bold)).foregroundStyle(Color(tone: light.tone))
                    .lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(light.spoken)
    }
}

/// The bottom bar: small uppercase text, as in Syndicate's "NETWORK: MASTER | 124.00". Each light's dot and word take
/// its state color, as in the big lights; labels stay gray. Reads the same as `StatusPresentation.line`.
struct StatusLineView: View {
    let presentation: StatusPresentation

    var body: some View {
        styledLine
            .font(Theme.ui(10, .semibold))
            .foregroundStyle(Theme.caption)
            // No scaling and no cut words: StatusPresentation already dropped whole parts to fit (#66).
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.background)
            // One sentence line for VoiceOver, with no "black circle" or "middle dot" (#67).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.spokenLine)
    }

    private var styledLine: Text {
        // Non-breaking spaces inside a part, so a part is never split if the line ever has to break.
        func keep(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "\u{00A0}") }
        let separator = Text(" · ").foregroundStyle(Theme.caption)
        var line = Text("")
        for (index, part) in presentation.lineParts.enumerated() {
            if index > 0 { line = line + separator }
            if let label = part.label {
                line = line + Text(keep(label.uppercased()) + "\u{00A0}").foregroundStyle(Theme.caption)
                    + Text(keep("● " + part.word.uppercased())).foregroundStyle(Color(tone: part.tone))
            } else {
                // DECK reads as a caption; MASTER keeps its orange.
                line = line + Text(keep(part.word.uppercased())).foregroundStyle(part.tone == .idle ? Theme.caption : Color(tone: part.tone))
            }
        }
        return line
    }
}

/// Syndicate's flat button: a slightly lighter gray, an edge and a small radius. Keyboard focus draws a ring, hover
/// lifts the fill, and a selected one (a tab, a deck) gets a bar and bold text, not just a fill (#67).
struct FlatButtonStyle: ButtonStyle {
    var selected: Bool
    #if DEBUG
    /// Snapshots only: draw the focus ring without real keyboard focus.
    var showsFocusForSnapshot = false
    #endif

    init(selected: Bool = false) { self.selected = selected }

    /// The older name, from the Diagnostics tabs (#26): raised is selected.
    init(raised: Bool) { self.selected = raised }

    func makeBody(configuration: Configuration) -> some View {
        #if DEBUG
        FlatButton(configuration: configuration, selected: selected, forcedFocus: showsFocusForSnapshot)
        #else
        FlatButton(configuration: configuration, selected: selected, forcedFocus: false)
        #endif
    }

    private struct FlatButton: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let forcedFocus: Bool
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.corner)
            configuration.label
                .font(Theme.ui(Theme.Size.label, selected ? .heavy : .bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(configuration.isPressed || hovering || selected ? Theme.buttonRaised : Theme.button, in: shape)
                .overlay(alignment: .bottom) {
                    if selected {
                        Rectangle().fill(Color(\.selectedBar)).frame(height: 2).padding(.horizontal, Theme.Space.s)
                    }
                }
                .overlay(shape.strokeBorder(Color(\.buttonEdge), lineWidth: 1))
                .focusRing(focused || forcedFocus, shape: shape)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// A caption-sized text control (Quit, Copy details, a disclosure): it keeps the look it's given, and adds the focus
/// ring and a hover lift (#67).
struct CaptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Quiet(configuration: configuration)
    }

    private struct Quiet: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .brightness(hovering ? 0.15 : 0)
                .padding(.horizontal, Theme.Space.xs)
                .focusRing(focused, shape: RoundedRectangle(cornerRadius: Theme.corner))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// A plain text button (a link such as "Setup guide…", a disclosure): no fill, but the same focus ring (#67).
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkButton(configuration: configuration)
    }

    private struct LinkButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.ui(Theme.Size.body, .semibold))
                .foregroundStyle(hovering || configuration.isPressed ? Theme.text : Theme.caption)
                .padding(.horizontal, Theme.Space.xs)
                .focusRing(focused, shape: RoundedRectangle(cornerRadius: Theme.corner))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// A 2 pt ring in the text color just outside the view, for keyboard focus.
    func focusRing(_ shown: Bool, shape: some InsettableShape) -> some View {
        overlay(shape.inset(by: -3).stroke(Theme.text, lineWidth: 2).opacity(shown ? 1 : 0))
    }
}

extension EnvironmentValues {
    /// The deck colors the badges draw (#123), from the Coordinator's status.
    @Entry var deckColors: DeckColors = .defaults
}

extension RGB {
    /// From Core's [r, g, b], 0-255.
    init(deckColor rgb: [Int]) {
        let channel = { (index: Int) in UInt32(clamping: rgb.indices.contains(index) ? max(0, min(255, rgb[index])) : 0) }
        self.init(hex: channel(0) << 16 | channel(1) << 8 | channel(2))
    }
}
