/// Everything the Coordinator reacts to, in one Sendable type.
public enum PipeEvent: Equatable, Sendable {
    case midi(MIDIEvent, source: MIDIEndpoint.ID)
    /// One UDP datagram from Syndicate, still OSC-encoded.
    case udp([UInt8])
    case tick
}

/// One ordered stream fed by every adapter: the CoreMIDI callback, the UDP reader and the tick timer.
///
/// Each producer's events arrive in the order it sent them. Across producers there is only arrival order.
public struct EventPipe: Sendable {
    public let events: AsyncStream<PipeEvent>
    public let producer: Producer

    public init() {
        // Unbounded: a dropped note off would leave a held button stuck.
        let (stream, continuation) = AsyncStream<PipeEvent>.makeStream(bufferingPolicy: .unbounded)
        events = stream
        producer = Producer(continuation: continuation)
    }

    /// Safe from any thread, including the CoreMIDI realtime thread. Every call is synchronous and never waits.
    public struct Producer: Sendable {
        let continuation: AsyncStream<PipeEvent>.Continuation

        public func midi(_ event: MIDIEvent, source: MIDIEndpoint.ID) { continuation.yield(.midi(event, source: source)) }
        public func udp(_ datagram: [UInt8]) { continuation.yield(.udp(datagram)) }
        public func tick() { continuation.yield(.tick) }
        public func finish() { continuation.finish() }
    }
}
