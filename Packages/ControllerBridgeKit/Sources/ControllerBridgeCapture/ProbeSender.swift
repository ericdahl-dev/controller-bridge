/// What reaches the controller during the LED probe (#187). It takes only note-on, note-off and CC messages (never
/// SysEx, system messages or the channel mode CCs 120-127, to hardware we don't know), lets one out per `interval` at
/// most, and knows what it lit so `enqueueAllOff` can turn it all off.
public struct ProbeSender: Sendable {
    /// The least time between two messages, in seconds.
    public static let interval = 0.1

    private var queue: [[UInt8]] = []
    private var lastSent: Double?
    /// What's lit on the controller, as status and number, in the order first lit: from what went out, not what's
    /// queued.
    private var lit: [[UInt8]] = []

    public init() {}

    /// Queues a message. Refused (false) unless it's a three-byte note-on, note-off or CC (below 120) with 7-bit data.
    @discardableResult
    public mutating func enqueue(_ message: [UInt8]) -> Bool {
        guard message.count == 3, [0x80, 0x90, 0xB0].contains(message[0] & 0xF0), message[1] < 0x80, message[2] < 0x80,
            !(message[0] & 0xF0 == 0xB0 && message[1] >= 120)
        else { return false }
        queue.append(message)
        return true
    }

    /// Forgets what's queued but not yet sent (such as the next probe's light), keeping what's lit known.
    public mutating func dropPending() { queue.removeAll() }

    /// Queues an off message for everything that will be lit once the queue has gone out.
    public mutating func enqueueAllOff() {
        var projected = lit
        for message in queue { Self.apply(message, to: &projected) }
        for key in projected { enqueue(key + [0]) }
    }

    public var hasPending: Bool { !queue.isEmpty }

    /// The messages to send now: at most one, if `interval` has passed since the last.
    public mutating func due(at now: Double) -> [[UInt8]] {
        guard !queue.isEmpty, lastSent.map({ now - $0 >= Self.interval - 1e-9 }) ?? true else { return [] }
        lastSent = now
        let message = queue.removeFirst()
        Self.apply(message, to: &lit)
        return [message]
    }

    private static func apply(_ message: [UInt8], to lit: inout [[UInt8]]) {
        let kind: UInt8 = message[0] & 0xF0 == 0xB0 ? 0xB0 : 0x90
        let key = [kind | (message[0] & 0x0F), message[1]]
        if message[0] & 0xF0 == 0x80 || message[2] == 0 { lit.removeAll { $0 == key } } else if !lit.contains(key) { lit.append(key) }
    }
}
