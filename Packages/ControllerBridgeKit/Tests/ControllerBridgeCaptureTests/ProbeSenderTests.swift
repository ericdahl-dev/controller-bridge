import ControllerBridgeCapture
import Testing

/// What reaches the controller during the LED probe (#187): only note and CC messages, one per 100 ms at most, and
/// everything it lit turned off at the end.
@Suite("Probe sender")
struct ProbeSenderTests {
    func accepts(_ sender: inout ProbeSender, _ message: [UInt8]) -> Bool { sender.enqueue(message) }
    func due(_ sender: inout ProbeSender, _ now: Double) -> [[UInt8]] { sender.due(at: now) }

    @Test("Only note-on, note-off and CC are accepted; SysEx, system, pitch bend and short messages are refused")
    func safeOnly() {
        var sender = ProbeSender()
        #expect(accepts(&sender, [0x90, 1, 127]))
        #expect(accepts(&sender, [0x80, 1, 0]))
        #expect(accepts(&sender, [0xB3, 20, 64]))
        #expect(!accepts(&sender, [0xF0, 0x00, 0x20, 0x7F, 0xF7]))
        #expect(!accepts(&sender, [0xF8]))
        #expect(!accepts(&sender, [0xE0, 0, 64]))
        #expect(!accepts(&sender, [0xC0, 5]))
        #expect(!accepts(&sender, [0x90, 1]))
        #expect(!accepts(&sender, [0x90, 0x81, 1]))
    }

    @Test("Rate-limited: one message per 100 ms at most, in order")
    func rateLimited() {
        var sender = ProbeSender()
        _ = sender.enqueue([0x90, 1, 127])
        _ = sender.enqueue([0x90, 2, 127])
        _ = sender.enqueue([0x90, 3, 127])
        #expect(due(&sender, 10.00) == [[0x90, 1, 127]])
        #expect(due(&sender, 10.05) == [])
        #expect(due(&sender, 10.10) == [[0x90, 2, 127]])
        #expect(due(&sender, 10.50) == [[0x90, 3, 127]])
        #expect(due(&sender, 11.00) == [])
    }

    @Test("allOff turns off everything still lit, once each; a value of 0 or a note-off counts as off already")
    func allOff() {
        var sender = ProbeSender()
        for message: [UInt8] in [[0x90, 1, 127], [0x90, 2, 64], [0x90, 2, 0], [0xB1, 20, 127], [0x90, 32, 48], [0x80, 32, 0]] {
            _ = sender.enqueue(message)
        }
        sender.enqueueAllOff()
        var sent: [[UInt8]] = []
        var now = 0.0
        while sender.hasPending {
            sent += sender.due(at: now)
            now += 0.1
        }
        #expect(Array(sent.suffix(2)) == [[0x90, 1, 0], [0xB1, 20, 0]])
        sender.enqueueAllOff()
        #expect(!sender.hasPending)
    }

    @Test("Channel mode messages (CC 120-127, such as Local Control and All Notes Off) are refused")
    func channelMode() {
        var sender = ProbeSender()
        #expect(accepts(&sender, [0xB0, 119, 127]))
        #expect(!accepts(&sender, [0xB0, 120, 0]))
        #expect(!accepts(&sender, [0xB0, 122, 0]))
        #expect(!accepts(&sender, [0xB5, 127, 0]))
    }

    @Test("Dropping what's queued keeps what's lit known, so all-off still turns it off")
    func dropPending() {
        var sender = ProbeSender()
        _ = sender.enqueue([0x90, 1, 127])
        _ = due(&sender, 0)
        _ = sender.enqueue([0x90, 1, 0])
        _ = sender.enqueue([0x90, 2, 127])
        sender.dropPending()  // note 2 never went out, and note 1's off didn't either
        sender.enqueueAllOff()
        #expect(due(&sender, 1) == [[0x90, 1, 0]])
        #expect(!sender.hasPending)
    }
}
