// Open Sound Control 1.0 messages and bundles. Pure encoding, no networking.

/// One OSC argument.
public enum OSCArgument: Equatable, Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
}

/// An OSC message: an address and its arguments.
public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [OSCArgument]

    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    public func encoded() -> [UInt8] {
        var out: [UInt8] = []
        out.appendOSCString(address)
        var tags = ","
        for argument in arguments {
            switch argument {
            case .int: tags += "i"
            case .float: tags += "f"
            case .string: tags += "s"
            }
        }
        out.appendOSCString(tags)
        for argument in arguments {
            switch argument {
            case .int(let value): out.appendBigEndian(UInt32(bitPattern: value))
            case .float(let value): out.appendBigEndian(value.bitPattern)
            case .string(let value): out.appendOSCString(value)
            }
        }
        return out
    }
}

/// A received OSC packet, flattened to its messages in order.
public struct OSCPacket: Equatable, Sendable {
    public var messages: [OSCMessage]

    public init(decoding bytes: [UInt8]) throws(OSCError) {
        var reader = OSCReader(bytes[...])
        messages = [try reader.message()]
    }
}

public enum OSCError: Error, Equatable {
    case truncated
    case malformed(String)
}

private struct OSCReader {
    var bytes: ArraySlice<UInt8>

    init(_ bytes: ArraySlice<UInt8>) { self.bytes = bytes }

    mutating func message() throws(OSCError) -> OSCMessage {
        let address = try string()
        guard address.hasPrefix("/") else { throw .malformed("address must start with /") }
        let tags = try string()
        guard tags.hasPrefix(",") else { throw .malformed("missing type tag string") }
        var arguments: [OSCArgument] = []
        for tag in tags.utf8.dropFirst() {
            switch tag {
            case UInt8(ascii: "i"): arguments.append(.int(Int32(bitPattern: try uint32())))
            case UInt8(ascii: "f"): arguments.append(.float(Float(bitPattern: try uint32())))
            case UInt8(ascii: "s"): arguments.append(.string(try string()))
            default: throw .malformed("unsupported type tag")
            }
        }
        return OSCMessage(address, arguments)
    }

    mutating func take(_ count: Int) throws(OSCError) -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count else { throw .truncated }
        let taken = bytes.prefix(count)
        bytes = bytes.dropFirst(count)
        return taken
    }

    mutating func uint32() throws(OSCError) -> UInt32 {
        try take(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func string() throws(OSCError) -> String {
        guard let end = bytes.firstIndex(of: 0) else { throw .truncated }
        let length = end - bytes.startIndex
        let value = String(decoding: bytes[bytes.startIndex..<end], as: UTF8.self)
        _ = try take((length + 1 + 3) & ~3)
        return value
    }
}

private extension Array where Element == UInt8 {
    mutating func appendOSCString(_ string: String) {
        append(contentsOf: string.utf8)
        append(0)
        while count % 4 != 0 { append(0) }
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
    }
}
