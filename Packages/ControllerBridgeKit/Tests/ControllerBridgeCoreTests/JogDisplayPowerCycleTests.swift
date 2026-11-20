import Foundation
@testable import ControllerBridgeCore
import Testing

/// After a power cycle (#606): the top panel may miss the hello, so it's sent again until it answers; and the display
/// chip's own boot sequence covers the host's images until it says ready (its first 10 reply), so the show then goes
/// again. Only messages the app already sends, newly timed.
@Suite("Jog display after a power cycle")
struct JogDisplayPowerCycleTests {
    typealias DriverRig = JogDisplayDriverTests.DriverRig

    /// Ticks the driver every 0.1 s up to `until`, noting when each hello pair went out.
    static func run(_ rig: DriverRig, from start: Double = 0, until end: Double) -> [Double] {
        var times: [Double] = []
        var t = start
        while t <= end + 1e-9 {
            rig.clock.now = t
            let before = rig.port.controller.count
            rig.driver.tick()
            if rig.port.controller.count > before {
                #expect(Array(rig.port.controller.dropFirst(before)) == JogDisplay.hello)
                times.append((t * 10).rounded() / 10)
            }
            t += 0.1
        }
        return times
    }

    @Test("No answer to the hello: the same hello pair again at 1, 3, 7, 15 and 31 s, then never")
    func helloAgain() {
        let rig = DriverRig()
        rig.driver.connect()
        #expect(Self.run(rig, until: 120) == [1, 3, 7, 15, 31])
    }
}
