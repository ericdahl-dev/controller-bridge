/// What reaches the controller during the LED probe (#187). It takes only note-on, note-off and CC messages (never
/// SysEx or anything else, to hardware we don't know), lets one out per `interval` at most, and remembers what it lit
/// so `enqueueAllOff` can turn it all off.
public struct ProbeSender: Sendable {
    /// The least time between two messages, in seconds.
    public static let interval = 0.1

    private var queue: [[UInt8]] = []
    private var lastSent: Double?
    /// What's lit, as status and number, in the order first lit.
    private var lit: [[UInt8]] = []

    public init() {}

    /// Queues a message. Refused (false) unless it's a three-byte note-on, note-off or CC with 7-bit data.
    @discardableResult
    public mutating func enqueue(_ message: [UInt8]) -> Bool {
        guard message.count == 3, [0x80, 0x90, 0xB0].contains(message[0] & 0xF0), message[1] < 0x80, message[2] < 0x80 else {
            return false
        }
        queue.append(message)
        let kind = message[0] & 0xF0 == 0xB0 ? 0xB0 : 0x90
        let key = [UInt8(kind) | (message[0] & 0x0F), message[1]]
        let off = message[0] & 0xF0 == 0x80 || message[2] == 0
        if off { lit.removeAll { $0 == key } } else if !lit.contains(key) { lit.append(key) }
        return true
    }

    /// Queues an off message for everything still lit.
    public mutating func enqueueAllOff() {
        for key in lit { enqueue(key + [0]) }
    }

    public var hasPending: Bool { !queue.isEmpty }

    /// The messages to send now: at most one, if `interval` has passed since the last.
    public mutating func due(at now: Double) -> [[UInt8]] {
        guard !queue.isEmpty, lastSent.map({ now - $0 >= Self.interval - 1e-9 }) ?? true else { return [] }
        lastSent = now
        return [queue.removeFirst()]
    }
}
