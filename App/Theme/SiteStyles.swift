// The site's components in the app (#171): pill buttons, a segmented control, chips and cards, on Syndicate's tokens.
// Every control keeps #67's contract: a focus ring on keyboard focus, a hover step, and selection shown by more than
// a fill. Bodies stay small for the CI Xcode 26.6 optimizer (#65).
import ControllerBridgePresentation
import SwiftUI

extension Theme {
    /// Grouped cards on the window (#171).
    static let surface = Color(\.surface)

    /// Corner radii: small for badges, fields and popups; medium for cards. Pills are fully round.
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
    }

    /// The site's 4 pt spacing scale (#171).
    enum Step {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
    }

    /// A mono label over a value or a row, in natural case (#171): "Controller", "Settings → OSC".
    static let labelFont = data(11, .medium)
}

/// The site's pill buttons (#171). Primary is Signal Green with dark ink, for a window's one finishing action;
/// secondary is a tonal fill; quiet is a text link.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    var small = false
    /// Stretch to the width it's given, as the panel's Settings… and Diagnostics… pair does.
    var fills = false
    /// A quiet button's own color, such as the demo toggle's orange while on.
    var color: Color?
    #if DEBUG
    /// Snapshots only: draw the focus ring without real keyboard focus.
    var showsFocusForSnapshot = false
    #endif

    func makeBody(configuration: Configuration) -> some View {
        #if DEBUG
        Pill(configuration: configuration, style: self, forcedFocus: showsFocusForSnapshot)
        #else
        Pill(configuration: configuration, style: self, forcedFocus: false)
        #endif
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let style: PillButtonStyle
        let forcedFocus: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.forcesIncreasedContrast) private var forced
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.ui(style.small ? 12 : 13, .medium))
                .foregroundStyle(ink)
                .lineLimit(1)
                .padding(.horizontal, style.kind == .quiet ? Theme.Step.x2 : (style.small ? Theme.Step.x3 : 14))
                .frame(maxWidth: style.fills ? .infinity : nil, minHeight: style.small ? 26 : 30)
                .background(fill, in: Capsule())
                .overlay(edge)
                .opacity(enabled ? 1 : 0.45)
                .ringOnFocus(focused || forcedFocus, shape: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }

        private var lifted: Bool { enabled && (hovering || configuration.isPressed) }
        /// A disabled primary turns tonal: a faded green still looks like something to press.
        private var kind: PillButtonStyle.Kind { style.kind == .primary && !enabled ? .secondary : style.kind }

        private var ink: Color {
            switch kind {
            case .primary: Color(\.onAccent)
            case .secondary: Theme.text
            case .quiet: style.color ?? (lifted ? Theme.text : Theme.caption)
            }
        }

        private var fill: some ShapeStyle {
            switch kind {
            case .primary: AnyShapeStyle(Color(\.accent).opacity(lifted ? 0.85 : 1))
            // The hover step is the text color at 14% over the tonal fill, so it shows (agent2's review of #171).
            case .secondary: AnyShapeStyle(lifted ? Theme.text.opacity(0.14) : Theme.buttonRaised)
            case .quiet: AnyShapeStyle(Color.clear)
            }
        }

        /// No edge, as on the site: the label names the button (#67 item 4). With Increase Contrast on, a 3:1 edge.
        @ViewBuilder private var edge: some View {
            if (contrast == .increased || forced) && style.kind != .quiet {
                Capsule().strokeBorder(Color(\.buttonEdge), lineWidth: 1)
            }
        }
    }
}

/// Pills in a tonal track (#171): the Diagnostics tabs, Ring colors. The selected one is filled with the text color,
/// its label heavier, and it carries the selected trait: never a fill alone (#67).
struct SegmentedPills<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.forcesIncreasedContrast) private var forced

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection = option }
                    .buttonStyle(SegmentStyle(selected: option == selection))
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.buttonRaised, in: Capsule())
        // With Increase Contrast on, the track gets a 3:1 edge, as the pills do.
        .overlay { if contrast == .increased || forced { Capsule().strokeBorder(Color(\.buttonEdge), lineWidth: 1) } }
    }
}

private struct SegmentStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Segment(configuration: configuration, selected: selected)
    }

    private struct Segment: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.ui(12, selected ? .semibold : .medium))
                .foregroundStyle(selected ? Theme.panel : (hovering ? Theme.text : Theme.caption))
                .padding(.horizontal, Theme.Step.x3)
                .frame(minHeight: 24)
                .background(selected ? Theme.text : Color.clear, in: Capsule())
                .ringOnFocus(focused, shape: Capsule())
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// A small tinted pill with a dot and a word, such as UNMAPPED (#171). The word carries the meaning.
struct ToneChip: View {
    let word: String
    let tone: StatusLight.Tone
    /// What VoiceOver says, when the word alone isn't enough ("Unmapped").
    var spoken: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(tone: tone)).frame(width: 6, height: 6)
            // The text color: a tone's color on its own tint misses AA (#174). PaletteTests check the pair.
            Text(word).font(Theme.data(10.5, .medium)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 18)
        .background(Color(tone: tone).opacity(Palette.chipTint), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? word)
    }
}

extension EnvironmentValues {
    /// Draws the Increase Contrast look regardless of the system setting. For snapshots, since colorSchemeContrast
    /// can't be set (#174).
    @Entry var forcesIncreasedContrast = false
}

extension View {
    /// A grouped card, as the site's: the surface color with a medium radius (#171).
    func card() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
    }

    /// The focus ring for a filled control: a 2 pt gap in the window color, then a 2 pt ring in the text color, so it
    /// shows on the green pill too (#67, #171).
    func ringOnFocus(_ shown: Bool, shape: some InsettableShape) -> some View {
        overlay {
            ZStack {
                shape.inset(by: -2).stroke(Theme.panel, lineWidth: 2)
                shape.inset(by: -4).stroke(Theme.text, lineWidth: 2)
            }
            .opacity(shown ? 1 : 0)
        }
    }
}
