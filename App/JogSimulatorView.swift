// Diagnostics › Jog display (#221): a live copy of what the LC6000's jog display shows, one round preview per deck.
// The picture comes from the upload's own renderer (ControllerBridgeRender, pinned equal by a test); the state, words
// and rate limit from ControllerBridgePresentation (tested). This is only the window part.
import ControllerBridgeCore
import ControllerBridgePresentation
import ControllerBridgeRender
import CoreGraphics
import Observation
import SwiftUI

/// The simulator's state on the main actor, fed by the jog display driver's events (BridgeHost hops each one here).
@MainActor @Observable
final class JogSimulatorLog {
    private(set) var sim = JogSimulator()
    /// Each deck's last uploaded content: what its preview draws.
    private(set) var contents: [Int: JogDisplayContent] = [:]
    /// Each deck's needle redraws at most 30 times a second (#221), whatever rate it arrives at.
    @ObservationIgnored private var needleLimiters: [Int: RedrawLimiter<Int>] = [:]

    func apply(_ event: JogDisplayEvent, at now: Date = .now) {
        switch event {
        case .connected: sim.apply(.connected)
        case .disconnected: sim.apply(.disconnected)
        case .uploadStarted(let slot, let content, let bytes):
            contents[content.deck] = content
            sim.apply(.uploadStarted(slot: Int(slot), deck: content.deck, bytes: bytes, at: now))
        case .shown(let slot): sim.apply(.shown(slot: Int(slot)))
        case .failed: sim.apply(.failed)
        // The unit's needle is the front deck's, which deckMarker already brings; the simulator draws every deck's.
        case .marker: break
        case .deckMarker(let deck, let pitchBend):
            var limiter = needleLimiters[deck] ?? RedrawLimiter<Int>(interval: 1.0 / 30)
            if let value = limiter.offer(pitchBend, at: now.timeIntervalSinceReferenceDate) { sim.apply(.marker(deck: deck, pitchBend: value)) }
            needleLimiters[deck] = limiter
        // The master clock's beat: the lit segment on every deck (#165).
        case .masterBeat(let beat): sim.apply(.masterBeat(beat))
        case .playLight(let on): sim.apply(.playing(on))
        // Every deck's content, live (#221): the simulator draws all of them, not only the one uploaded.
        case .preview(let content): contents[content.deck] = content
        }
    }

    /// The display timer: each deck's needle held back by its limiter, once its interval has passed.
    func tick(_ now: Date) {
        for deck in needleLimiters.keys.sorted() {
            if let value = needleLimiters[deck]?.tick(at: now.timeIntervalSinceReferenceDate) { sim.apply(.marker(deck: deck, pitchBend: value)) }
        }
    }
}

/// The tab's content: a preview per deck the unit has shown, each with its readout.
struct JogDisplayPane: View {
    let log: JogSimulatorLog
    let empty: String
    /// Off only for snapshots, which draw once.
    var animates = true

    var body: some View {
        let decks = log.contents.keys.sorted()
        Group {
            if decks.isEmpty {
                Text(empty)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Step.x3)], spacing: Theme.Step.x4) {
                        ForEach(decks, id: \.self) { deck in
                            if let content = log.contents[deck] { JogDeckPreview(deck: deck, content: content, sim: log.sim) }
                        }
                    }
                    .padding(Theme.Step.x4)
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .background {
            // The display timer: lets a held-back marker through, at most 30 times a second.
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    Color.clear.onChange(of: context.date) { _, now in log.tick(now) }
                }
            }
        }
    }
}

/// One deck's display, scaled up, with the play light and the readout under it.
private struct JogDeckPreview: View {
    let deck: Int
    let content: JogDisplayContent
    let sim: JogSimulator

    var body: some View {
        let onUnit = sim.onUnit(deck: deck)
        let card = sim.card(deck: deck)
        let litBeat = sim.litBeat(deck: deck)
        let summary = JogDeckSummary(deck: deck, title: content.title, key: content.key, bpm: content.bpm, beat: litBeat)
        VStack(spacing: Theme.Step.x2) {
            if let image = Self.image(JogDisplayRenderer.simulatorImage(content, litBeat: litBeat, marker: sim.markerTurns(deck: deck))) {
                Image(decorative: image, scale: 1)
                    .interpolation(.high)
                    .resizable()
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            }
            HStack(spacing: Theme.Step.x1) {
                Circle()
                    .fill(sim.playing(deck: deck) ? Theme.live : Theme.hairline)
                    .frame(width: 8, height: 8)
                Text(sim.playing(deck: deck) ? "Playing" : "Paused")
                    .font(Theme.ui(12)).foregroundStyle(Theme.text)
            }
            // What really reached the unit (#318): the deck it shows carries the readout; a preview says so.
            Text(card)
                .font(Theme.data(10))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(onUnit ? Theme.text : Theme.caption)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Step.x2)
        .overlay {
            if onUnit { RoundedRectangle(cornerRadius: Theme.Radius.medium).stroke(Theme.live, lineWidth: 1.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.spoken)
        .accessibilityValue(card.replacingOccurrences(of: "\n", with: ". "))
    }

    /// The renderer's RGBA (198×198, premultiplied, top row first) as an image.
    static func image(_ rgba: [UInt8]) -> CGImage? {
        let size = JogDisplayRenderer.size
        guard rgba.count == size * size * 4, let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
