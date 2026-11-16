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

    /// The destination on the same device entity as `source` (the port pair CoreMIDI groups together), so with two
    /// units of one name the probe reaches the one being captured. Nil when the entity has no destination.
    static func destination(pairedWith source: MIDIEndpoint) -> MIDIEndpoint? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        var entity = MIDIEntityRef()
        guard MIDIObjectFindByUniqueID(source.id, &object, &type) == noErr, object != 0,
            MIDIEndpointGetEntity(object, &entity) == noErr, entity != 0, MIDIEntityGetNumberOfDestinations(entity) > 0
        else { return nil }
        let ref = MIDIEntityGetDestination(entity, 0)
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(ref, kMIDIPropertyUniqueID, &id)
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name)
        return MIDIEndpoint(id: id, name: (name?.takeRetainedValue() as String?) ?? "MIDI \(id)")
    }

    func close() {
        MIDIPortDispose(port)
        MIDIClientDispose(client)
    }
}
