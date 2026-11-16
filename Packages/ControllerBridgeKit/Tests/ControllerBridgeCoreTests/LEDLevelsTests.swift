import Foundation
@testable import ControllerBridgeCore
import Testing

/// Button LED levels from the profile (#194): full, dim and off, the LC6000's 127, 1 and 0 unless a profile says.
@Suite("LED levels")
struct LEDLevelsTests {
    @Test("Left out, the levels are the LC6000's 127, 1 and 0; a partial override keeps the rest")
    func decoding() throws {
        #expect(try JSONDecoder().decode(Mapping.LEDLevels.self, from: Data("{}".utf8)) == .init(full: 127, dim: 1, off: 0))
        #expect(try JSONDecoder().decode(Mapping.LEDLevels.self, from: Data(#"{"dim": 20}"#.utf8)) == .init(full: 127, dim: 20, off: 0))
    }

    @Test("The bundled LC6000 is 127, 1 and 0, as before #194")
    func lc6000() throws {
        #expect(try Mapping.bundledDefault().leds.levels == .init(full: 127, dim: 1, off: 0))
    }
}
