// The UDP transport. Not unit-tested: the smoke script (scripts/smoke.sh) covers it.
import Darwin
import Dispatch
import LC6000Core

/// Sends each OSC message as one datagram to Syndicate. Loopback only, so there is no local-network prompt.
final class UDPOSCSender: OSCSender {
    private let socket: Int32

    init(host: String, port: Int) throws(UDPError) {
        socket = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard socket >= 0 else { throw .errno("socket", errno) }
        let address = try ipv4(host, port)
        // A connected UDP socket: plain send(), and the kernel keeps the destination.
        let status = withSockaddr(address) { Darwin.connect(socket, $0, $1) }
        guard status == 0 else { close(socket); throw .errno("connect", errno) }
    }

    deinit { close(socket) }

    func send(_ message: OSCMessage) {
        let bytes = message.encoded()
        // Nothing is listening until Syndicate starts: ECONNREFUSED is normal, so a lost datagram is not an error.
        _ = bytes.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
    }
}

/// Listens for Syndicate's OSC feedback and puts each datagram into the EventPipe.
final class FeedbackListener: Sendable {
    private let source: any DispatchSourceRead

    private init(source: any DispatchSourceRead) { self.source = source }

    /// Fails with `.errno("bind", EADDRINUSE)` when another app has the port: the status shows it, nothing crashes.
    nonisolated static func start(host: String, port: Int, producer: EventPipe.Producer) throws(UDPError) -> FeedbackListener {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw .errno("socket", errno) }
        let address: sockaddr_in
        do { address = try ipv4(host, port) } catch { close(fd); throw error }
        // No SO_REUSEPORT: two listeners would split the feedback with no error.
        guard withSockaddr(address, { bind(fd, $0, $1) }) == 0 else {
            let code = errno
            close(fd)
            throw .errno("bind", code)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "dev.ericdahl.LC6000Bridge.feedback"))
        // Made here, outside any actor: written in main-actor code, this handler traps on its queue (#14 spike).
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 { producer.udp(Array(buffer[0..<count])) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return FeedbackListener(source: source)
    }

    func stop() { source.cancel() }
}

enum UDPError: Error, CustomStringConvertible {
    case badAddress(String)
    case errno(String, Int32)

    var isAddressInUse: Bool { if case .errno(_, EADDRINUSE) = self { true } else { false } }

    var description: String {
        switch self {
        case .badAddress(let host): "\(host) is not an IPv4 address"
        case .errno(let call, let code): "\(call): \(String(cString: strerror(code)))"
        }
    }
}

private func ipv4(_ host: String, _ port: Int) throws(UDPError) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(truncatingIfNeeded: port).bigEndian
    guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { throw .badAddress(host) }
    return address
}

private func withSockaddr<R>(_ address: sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
    withUnsafePointer(to: address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
}
