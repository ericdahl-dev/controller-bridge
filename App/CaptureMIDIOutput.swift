// The capture window's LED test output (#187). Not unit-tested: what it may send, and when, is the Kit's ProbeSender;
// the live path is on the manual checklist.
import CoreMIDI
import ControllerBridgeCore
import Foundation

/// An output port to one destination, opened only when the owner starts the LED test, and only to the controller's
/// main output (never a second port such as the LC6000's WD, #143).
final class CaptureMIDIOutput {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let destination: MIDIEndpointRef

    init?(destination endpoint: MIDIEndpoint) {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(endpoint.id, &object, &type) == noErr, object != 0, type == .destination,
            MIDIClientCreateWithBlock("ControllerBridge LED test" as CFString, &client, nil) == noErr,
            MIDIOutputPortCreate(client, "LED test out" as CFString, &port) == noErr
        else { return nil }
        destination = object
    }

    /// One three-byte channel voice message, as ProbeSender let it out.
    func send(_ message: [UInt8]) {
        guard message.count == 3 else { return }
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        var word = UInt32(0x2000_0000) | UInt32(message[0]) << 16 | UInt32(message[1]) << 8 | UInt32(message[2])
        MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
        MIDISendEventList(port, destination, &list)
    }

    func close() {
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }
}
