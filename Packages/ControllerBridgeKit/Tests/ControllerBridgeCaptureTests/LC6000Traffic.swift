/// LC6000 PRIME traffic for the capture tests, as (seconds, bytes).
///
/// HAND-BUILT, REPLACE WITH RECORDING: these are written from the hardware-confirmed LC6000 facts (the bundled profile
/// and #12, #121, #165), not recorded. A listen-only recording of the same gestures replaces them in a follow-up.
/// No djay traffic is used.
enum LC6000Traffic {
    typealias Take = [(time: Double, bytes: [UInt8])]

    /// Play on deck 1: note 1, channel 1, released with a note-off.
    static let play: Take = [(0.00, [0x90, 0x01, 0x7F]), (0.12, [0x80, 0x01, 0x00])]

    /// Cue on deck 1: note 2.
    static let cue: Take = [(0.00, [0x90, 0x02, 0x7F]), (0.15, [0x80, 0x02, 0x00])]
}

/// Other controllers' shapes the LC6000 doesn't send, so the inference is covered both ways. Hand-built.
enum OtherTraffic {
    /// A button released with a note-on at velocity 0, as many controllers do.
    static let noteOnZeroRelease: [(time: Double, bytes: [UInt8])] = [(0.00, [0x92, 0x0B, 0x7F]), (0.10, [0x92, 0x0B, 0x00])]
}
