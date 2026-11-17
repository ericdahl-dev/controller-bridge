// Syndicate subscriptions that are off, as a list (#261): the header, then a row each with Syndicate's own label in
// bold and what goes wrong without it. The same view in the panel's help and in Diagnostics › OSC Log. The words and
// order come from the tested HelpMessage; this is only the look and VoiceOver's reading.
import ControllerBridgePresentation
import SwiftUI

struct SubscriptionListView: View {
    let help: HelpMessage
    /// The panel's help reads at 13 pt; Diagnostics' notes at 12.
    var size: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Step.x2) {
            Text(help.text).font(Theme.ui(size)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Step.x2) {
                ForEach(help.subscriptions, id: \.name) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Step.x2) {
                        Circle().fill(Theme.attention).frame(width: 7, height: 7)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(Theme.ui(size, .semibold)).foregroundStyle(Theme.text)
                            Text(row.consequence).font(Theme.ui(size - 1)).foregroundStyle(Theme.caption)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    // One element per row: "Cues: hot cue pads stay dark".
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                }
            }
            // A list to VoiceOver: the count and header, then each row.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(help.subscriptionsLabel ?? help.text)
        }
    }
}
