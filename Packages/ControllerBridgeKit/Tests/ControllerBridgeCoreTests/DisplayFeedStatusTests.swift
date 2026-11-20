import ControllerBridgeCore
import Foundation
import Testing

/// The display feed's status line in Settings (#618): what it's doing, so a feed that can't send never fails silently.
/// Read from the setting and the feed's destination, with fake sockets: no network.
@Suite("Display feed: the status line")
struct DisplayFeedStatusTests {
    typealias Sinks = OSCDestinationTests.FakeSinks
    typealias Resolver = OSCDestinationTests.FakeResolver

    static let on = DisplayFeedSettings(enabled: true, host: "192.168.1.40", port: 9100)

    @Test("Off says so; on with nothing open yet is connecting; open is sending, to the host and port")
    func offConnectingSending() async {
        let sinks = Sinks()
        let destination = OSCDestinationTests.destination(sinks, Resolver())
        #expect(DisplayFeedStatus(DisplayFeedSettings(), destination) == .off)
        #expect(DisplayFeedStatus(Self.on, destination) == .connecting("192.168.1.40:9100"))
        _ = await destination.connect(host: "192.168.1.40", port: 9100)
        #expect(DisplayFeedStatus(Self.on, destination) == .sending("192.168.1.40:9100"))
        #expect(DisplayFeedStatus(Self.on, destination).text == "Sending to 192.168.1.40:9100")
        #expect(DisplayFeedStatus(DisplayFeedSettings(), destination).text == "Off")
        #expect(DisplayFeedStatus(Self.on, OSCDestinationTests.destination(Sinks(), Resolver())).text
            == "Connecting to 192.168.1.40:9100…")
    }
}
