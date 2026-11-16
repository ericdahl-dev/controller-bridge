/// Everything the Coordinator reacts to, in one Sendable type.
public enum PipeEvent: Equatable, Sendable {
    case midi(MIDIEvent, source: MIDIEndpoint.ID)
    /// One UDP datagram from Syndicate, still OSC-encoded.
    case udp([UInt8])
    case tick
    /// MIDI devices were added or removed: the Coordinator re-reads them.
    case devicesChanged
    /// The Mac is about to sleep, or just woke.
    case sleep
    case wake
    /// The Diagnostics window opened or closed (#26).
    case diagnostics(open: Bool)
    /// Start the LED sweep, `delay` seconds per color; or stop it part-way.
    case ledSweep(delay: Double)
    case stopLEDSweep
    /// The built-in demo controller (#64) on or off.
    case demo(on: Bool)
    /// Settings changes (#19), in order with the MIDI already queued.
    case setDeck(Int, controller: Int)
    case setDevices(input: MIDIEndpoint?, output: MIDIEndpoint?, controller: Int)
    case setLEDs(enabled: Bool)
    /// Quit: release everything and end the loop. Always the last event.
    case stop
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
        public func devicesChanged() { continuation.yield(.devicesChanged) }
        public func sleep() { continuation.yield(.sleep) }
        public func wake() { continuation.yield(.wake) }
        public func diagnostics(open: Bool) { continuation.yield(.diagnostics(open: open)) }
        public func ledSweep(delay: Double) { continuation.yield(.ledSweep(delay: delay)) }
        public func stopLEDSweep() { continuation.yield(.stopLEDSweep) }
        public func demo(on: Bool) { continuation.yield(.demo(on: on)) }
        public func setDeck(_ deck: Int, controller: Int) { continuation.yield(.setDeck(deck, controller: controller)) }
        public func setDevices(input: MIDIEndpoint?, output: MIDIEndpoint?, controller: Int) {
            continuation.yield(.setDevices(input: input, output: output, controller: controller))
        }
        public func setLEDs(enabled: Bool) { continuation.yield(.setLEDs(enabled: enabled)) }
        /// Quit. Queues the stop behind everything already sent, then closes the pipe, so nothing after it is handled.
        public func stop() {
            continuation.yield(.stop)
            continuation.finish()
        }
        public func finish() { continuation.finish() }
    }
}
