// The capture window's MIDI input (#186). Not unit-tested: the words-to-bytes conversion is in the Kit
// (CaptureMIDI), and the live path is on the manual checklist.
import CoreMIDI
import ControllerBridgeCapture
import ControllerBridgeCore
import Foundation

/// Listens to the ports being captured, on its own CoreMIDI client. It has an input port and no output port, so it
/// can't send anything to the controller. Each message is handed on with the port's index and the host time.
final class CaptureMIDIInput {
    private var client = MIDIClientRef()
    private var input = MIDIPortRef()

    /// `receive` gets each message's bytes, the time (system uptime, seconds) and the port's index in `sources`.
    /// Called on CoreMIDI's thread.
    init?(sources: [MIDIEndpoint], receive: @escaping @Sendable ([UInt8], Double, Int) -> Void) {
        guard MIDIClientCreateWithBlock("ControllerBridge capture" as CFString, &client, nil) == noErr,
            MIDIInputPortCreateWithProtocol(client, "Capture in" as CFString, ._1_0, &input, Self.receiveBlock(receive)) == noErr
        else { return nil }
        for (index, source) in sources.enumerated() {
            guard let ref = Self.find(source) else { continue }
            // The port's index rides along as the refCon, plus one so index 0 isn't a null pointer.
            MIDIPortConnectSource(input, ref, UnsafeMutableRawPointer(bitPattern: index + 1))
        }
    }

    /// Stops listening. Nothing arrives after this.
    func stop() {
        MIDIPortDispose(input)
        MIDIClientDispose(client)
    }

    private nonisolated static func receiveBlock(_ receive: @escaping @Sendable ([UInt8], Double, Int) -> Void) -> MIDIReceiveBlock {
        { list, refCon in
            let now = ProcessInfo.processInfo.systemUptime
            let port = Int(bitPattern: refCon) - 1
            for packet in list.unsafeSequence() {
                for bytes in CaptureMIDI.bytes(words: Array(packet.words())) { receive(bytes, now, port) }
            }
        }
    }

    private static func find(_ endpoint: MIDIEndpoint) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(endpoint.id, &object, &type) == noErr, object != 0 else { return nil }
        return object
    }
}
