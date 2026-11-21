import Darwin
import DeviceFinder
import Foundation

/// Listens to a deck panel's serial port (#685): opened read-only and non-blocking, DTR and RTS cleared together in
/// one call so the auto-reset circuit never sees one without the other, and nothing written. 115200 baud, the
/// panel's console. A later ticket may add a version question (#695); this one only reads.
struct ListeningSerial: PanelSerial {
    func listen(on port: String, for seconds: Double) async -> [String] {
        await Task.detached { Self.read(port, seconds) }.value
    }

    private static func read(_ port: String, _ seconds: Double) -> [String] {
        let fd = open(port, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var lines: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(fd, TIOCMBIC, &lines)
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { return [] }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CREAD | CLOCAL)
        options.c_cflag &= ~tcflag_t(HUPCL)  // no DTR drop on close
        cfsetspeed(&options, speed_t(B115200))
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { return [] }

        var text = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 { text.append(contentsOf: buffer[0..<count]) } else { usleep(20_000) }
        }
        return String(decoding: text, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
