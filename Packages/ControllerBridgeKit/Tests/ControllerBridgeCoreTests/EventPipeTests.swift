import Foundation
import ControllerBridgeCore
import Testing

@Suite struct EventPipeTests {
    @Test func oneProducerArrivesInOrderAndFinishEndsTheStream() async {
        let pipe = EventPipe()
        pipe.producer.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: -1_012_345)
        pipe.producer.tick()
        pipe.producer.udp([0x2F, 0x61])
        pipe.producer.finish()

        var got: [PipeEvent] = []
        for await event in pipe.events { got.append(event) }
        #expect(got == [.midi(.noteOn(channel: 0, note: 1, velocity: 127), source: -1_012_345), .tick, .udp([0x2F, 0x61])])
    }

    // Three OS threads stand in for the CoreMIDI realtime thread, the UDP reader and the timer. Each producer's
    // own sequence must arrive whole and in order. There is no global order across producers to check.
    @Test func eachProducerKeepsItsOwnOrderAcrossThreads() async {
        let count = 5_000
        let pipe = EventPipe()
        let producer = pipe.producer
        let group = DispatchGroup()
        for job in 0..<3 {
            group.enter()
            Thread.detachNewThread {
                for i in 0..<count {
                    switch job {
                    case 0: producer.midi(.controlChange(channel: 0, controller: UInt8(i / 128 % 128), value: UInt8(i % 128)), source: 42)
                    case 1: producer.udp([UInt8(i >> 8), UInt8(i & 0xFF)])
                    default: producer.tick()
                    }
                }
                group.leave()
            }
        }
        Thread.detachNewThread { group.wait(); producer.finish() }

        var midi: [Int] = [], udp: [Int] = [], ticks = 0
        for await event in pipe.events {
            switch event {
            case .midi(.controlChange(_, let high, let low), 42): midi.append(Int(high) * 128 + Int(low))
            case .udp(let bytes): udp.append(Int(bytes[0]) << 8 | Int(bytes[1]))
            case .tick: ticks += 1
            default: Issue.record("unexpected \(event)")
            }
        }
        #expect(midi == Array(0..<count))
        #expect(udp == Array(0..<count))
        #expect(ticks == count)
    }

    // The CoreMIDI realtime callback is synchronous, so the producer must be too: `fillWithoutAwaiting` is not
    // async, so it couldn't compile if a producer call awaited. With no reader attached, 100k sends must still
    // return at once (nothing waits for the consumer), and the reader later gets every one.
    @Test func producerCallsAreSynchronousAndNeverWaitForTheReader() async {
        let count = 100_000
        let pipe = EventPipe()
        let elapsed = ContinuousClock().measure { fillWithoutAwaiting(pipe.producer, count: count) }
        #expect(elapsed < .seconds(1))

        var received = 0
        for await _ in pipe.events { received += 1 }
        #expect(received == count)
    }
}

private func fillWithoutAwaiting(_ producer: EventPipe.Producer, count: Int) {
    for _ in 0..<count { producer.tick() }
    producer.finish()
}
