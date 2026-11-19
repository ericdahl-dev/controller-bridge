import ControllerBridgeCore
@testable import ControllerBridgeRender
import Testing

/// Image mode's uploads stay exactly as they are (#524): the drawn layout's changes (bigger time, smaller key/BPM, the
/// band ring, the stale chip) are drawn mode's only. Pinned as a hash of the upload's bytes for fixed contents.
@Suite("Jog display renderer: uploads unchanged")
struct JogDisplayUploadPinTests {
    /// FNV-1a, 64-bit.
    static func hash(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }

    static let contents: [(JogDisplayContent, UInt64)] = [
        (JogDisplayContent(deck: 2, color: [255, 0, 0], title: "Daybreak", artist: "Night Drive", key: "12A", bpm: 174,
                           playerType: "track"), 0x353F_95CC_9E7D_434D),
        (JogDisplayContent(deck: 3, color: [0, 255, 255], playerType: "osc"), 0x2775_21A5_7253_DC2A),
        (JogDisplayContent(deck: 4, color: [0, 128, 255]), 0x5D5B_2453_42AA_0FE1),
    ]

    @Test("The upload's bytes for fixed contents are today's")
    func pinned() {
        for (content, want) in Self.contents {
            #expect(Self.hash(JogDisplayRenderer.uploadImage(content)) == want)
        }
    }
}
