// What the capture window shows and speaks for a detected control (#186).

extension ControlFacts {
    /// A short readout: "CC 17 + 49 on ch 1, 14-bit, absolute".
    public var summary: String {
        switch kind {
        case .note: "Note \(number ?? 0) on ch \(channel)"
        case .pitchBend: "Pitch bend on ch \(channel)"
        case .cc:
            "CC \(number ?? 0)\(lsb.map { " + \($0)" } ?? "") on ch \(channel)\(lsb == nil ? "" : ", 14-bit"), "
                + (encoding.map(Self.shortName) ?? "encoding unclear")
        }
    }

    /// The readout in words VoiceOver reads well: "Control change 17 and 49 on channel 1, 14-bit, absolute".
    public var spoken: String {
        switch kind {
        case .note: "Note \(number ?? 0) on channel \(channel)"
        case .pitchBend: "Pitch bend on channel \(channel)"
        case .cc:
            "Control change \(number ?? 0)\(lsb.map { " and \($0)" } ?? "") on channel \(channel)\(lsb == nil ? "" : ", 14-bit"), "
                + (encoding.map(Self.spokenName) ?? "encoding unclear")
        }
    }

    private static func shortName(_ encoding: ControlEncoding) -> String {
        switch encoding {
        case .absolute: "absolute"
        case .twosComplement: "relative (two's complement)"
        case .offset64: "relative (offset 64)"
        case .signMagnitude: "relative (sign magnitude)"
        }
    }

    private static func spokenName(_ encoding: ControlEncoding) -> String {
        switch encoding {
        case .absolute: "absolute"
        case .twosComplement: "relative, two's complement"
        case .offset64: "relative, offset 64"
        case .signMagnitude: "relative, sign magnitude"
        }
    }
}
