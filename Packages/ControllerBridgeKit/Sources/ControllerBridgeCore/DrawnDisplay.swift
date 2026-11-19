// The drawn jog display's messages (#455): small state messages a unit with the custom display firmware draws itself,
// instead of uploaded images. Denon's frame on the WD port, one command byte for all of them and an op byte. The shared
// vectors (tools/lc6000-display-fw/vectors/messages.json) hold examples both this and the firmware's C are tested on.

/// The jog display firmware DeckBridge found on the unit (#456).
public enum DisplayFound: Equatable, Sendable {
    case denon
    /// Custom firmware that didn't answer as one that draws: uploaded images.
    case customImages
    case customDrawn(version: Int)

    /// What Settings shows.
    public var label: String {
        switch self {
        case .denon: "Denon"
        case .customImages: "Custom (images)"
        case .customDrawn(let version): "Custom (drawn display, protocol \(version))"
        }
    }
}

public enum DrawnDisplay {
    /// The command byte of every drawn-display message. A placeholder until #466 finds one Denon's dispatcher leaves
    /// free; the vectors file and the C side carry the same number.
    public static let command: UInt8 = 0x20
    /// The protocol version this app speaks.
    public static let version = 1

    /// What a deck holds, as the badge shows it (#209).
    public enum Player: UInt8, Sendable {
        case empty = 0, track, oscClip, midiClip, sequencer, other

        /// From Syndicate's player type: nil or "empty" is empty.
        public init(playerType: String?) {
            guard let type = playerType?.lowercased(), !type.isEmpty, type != "empty" else { self = .empty; return }
            if type == "track" { self = .track }
            else if type.contains("osc") { self = .oscClip }
            else if type.contains("midi") { self = .midiClip }
            else if type.contains("seq") { self = .sequencer }
            else { self = .other }
        }
    }

    public enum Message: Equatable, Sendable {
        /// "Can you draw?", with the newest version the host speaks.
        case capability(version: Int)
        case begin(version: Int)
        case end(version: Int)
        /// The deck in front: its number (1-4), color [r, g, b] (0-255 each) and what it holds.
        case deck(number: Int, color: [Int], player: Player)

        /// The SysEx frame for the WD port.
        public var bytes: [UInt8] {
            switch self {
            case .capability(let version): DrawnDisplay.frame(0x00, [UInt8(version & 0x7F)])
            case .begin(let version): DrawnDisplay.frame(0x01, [UInt8(version & 0x7F)])
            case .end(let version): DrawnDisplay.frame(0x02, [UInt8(version & 0x7F)])
            case .deck(let number, let color, let player):
                DrawnDisplay.frame(0x03, [UInt8(number & 0x7F)]
                    + color.prefix(3).flatMap { channel -> [UInt8] in
                        let value = min(max(channel, 0), 255)
                        return [UInt8(value >> 7), UInt8(value & 0x7F)]
                    } + [player.rawValue])
            }
        }
    }

    static func frame(_ op: UInt8, _ arguments: [UInt8]) -> [UInt8] {
        JogDisplay.frame(command, [op] + arguments)
    }

    /// The unit's answer to the capability question: its protocol version, or nil for anything else.
    public static func answer(_ message: [UInt8]) -> Int? {
        let head: [UInt8] = [0xF0, 0x00, 0x02, 0x0B, 0x01, 0x10, command, 0x00, 0x02, 0x00]
        guard message.count == 12, Array(message.prefix(10)) == head, message[11] == 0xF7,
              (1...0x7F).contains(message[10]) else { return nil }
        return Int(message[10])
    }
}
