import Foundation
@testable import ControllerBridgeCore
import Testing

/// A controller's color table (#197): the LC6000's rgb222, or a list of RGB-to-value entries matched by nearest RGB.
/// Expected values worked by hand (squared RGB distance).
@Suite("Color table")
struct ColorTableTests {
    static let list = ColorTable.list([
        .init(rgb: [255, 0, 0], value: 5), .init(rgb: [0, 255, 0], value: 9), .init(rgb: [0, 0, 255], value: 13),
        .init(rgb: [255, 255, 255], value: 3), .init(rgb: [0, 0, 0], value: 0),
    ])

    @Test("rgb222 is the LC6000's: red 48, orange 56, green 12, and a dim red lights red at level 1 (16)")
    func rgb222() {
        #expect([[255, 0, 0], [255, 128, 0], [0, 255, 0], [20, 0, 0], [0, 0, 0]].map { ColorTable.rgb222.velocity(for: $0) }
            == [48, 56, 12, 16, 0])
    }

    @Test("A list picks the nearest entry: (200, 30, 10) is red's 5; a tie (128, 128, 0) goes to the first entry, red")
    func nearest() {
        #expect(Self.list.velocity(for: [200, 30, 10]) == 5)
        #expect(Self.list.velocity(for: [128, 128, 0]) == 5)
        #expect(Self.list.velocity(for: [10, 240, 20]) == 9)
    }

    @Test("A list's dim fallback: (20, 0, 0) is nearest black, so it lights the nearest color instead, red; black is off")
    func dimFallback() {
        #expect(Self.list.velocity(for: [20, 0, 0]) == 5)
        #expect(Self.list.velocity(for: [0, 0, 0]) == 0)
    }

    @Test("Vivid: the LC6000's vivid velocity on rgb222; on a list, the vivid color's nearest entry (orange to red, 5)")
    func vivid() {
        #expect(ColorTable.rgb222.vivid(for: [255, 140, 0]) == vividVelocity(255, 140, 0))
        #expect(Self.list.vivid(for: [255, 140, 0]) == 5)
    }
}
