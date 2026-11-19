// What the drawn display's chip knows (#465), decoded from the same messages it gets, by the same rules as
// tools/lc6000-display-fw/src/dfw.c: the Diagnostics preview draws from this, so it shows what the chip would.

public struct DrawnDisplayState: Equatable, Sendable {
    /// The deck in front, as its deck message gave it.
    public struct Deck: Equatable, Sendable {
        public var number: Int
        public var color: [Int]
        public var player: DrawnDisplay.Player
    }

    /// Between begin and end.
    public private(set) var drawn = false
    public private(set) var deck: Deck?
    public private(set) var flags: DrawnDisplay.State = []
    /// The master beat, 1-4, or 0 with none.
    public private(set) var beat = 0
    /// The needle, 0-16383; nil until a needle message.
    public private(set) var needle: Int?
    /// Level and held peak, 0-127; nil until a meter message.
    public private(set) var meter: (level: Int, peak: Int)? {
        get { meterValue.map { ($0[0], $0[1]) } }
        set { meterValue = newValue.map { [$0.level, $0.peak] } }
    }
    private var meterValue: [Int]?
    /// Each text field's Windows-1252 codes (0x81 the box); empty for none.
    public private(set) var texts: [DrawnDisplay.TextField: [UInt8]] = [:]
    /// Whether a text has come since the deck changed: until then no words are drawn.
    public private(set) var textHeard = false
    /// Tenths of a BPM, 0 for none.
    public private(set) var tempo = 0
    /// 1/16384 beats from the master, negative behind; DrawnPhase.unknown until the deck's own comes.
    public private(set) var phase = DrawnPhase.unknown

    public init() {}

    /// Applies one whole message, F0 through F7, as the chip does; anything malformed or not ours changes nothing.
    /// Whether anything changed.
    @discardableResult
    public mutating func apply(_ bytes: [UInt8]) -> Bool {
        let before = self
        act(bytes)
        return self != before
    }

    private static let header: [UInt8] = [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, DrawnDisplay.command]

    /// Each op's one exact length, counting the op; nil for text (framed by len) and for an op this version doesn't take.
    private static func length(_ op: UInt8) -> Int? {
        switch op {
        case 0x00, 0x01, 0x02, 0x07, 0x08: 2
        case 0x05, 0x09, 0x0A, 0x0B: 3
        case 0x03: 9
        default: nil
        }
    }

    private mutating func act(_ bytes: [UInt8]) {
        let header = Self.header
        guard bytes.count >= header.count + 4, Array(bytes.prefix(header.count)) == header, bytes.last == 0xF7,
              bytes.dropFirst().dropLast().allSatisfy({ $0 < 0x80 }) else { return }
        let declared = Int(bytes[header.count]) << 7 | Int(bytes[header.count + 1])
        guard bytes.count == header.count + 3 + declared, declared > 0 else { return }
        let op = bytes[header.count + 2]
        let args = Array(bytes[(header.count + 3)..<(bytes.count - 1)])
        func word() -> Int { Int(args[0]) << 7 | Int(args[1]) }
        if op == 0x04 {
            guard declared >= 2, declared <= 2 + DrawnDisplay.textCap,
                  let field = DrawnDisplay.TextField(rawValue: args[0]), let codes = Self.decode(args.dropFirst()) else { return }
            guard drawn else { return }
            textHeard = true
            texts[field] = codes
            return
        }
        guard let length = Self.length(op), declared == length else { return }
        // Version 0 is malformed.
        if op <= 0x02, args[0] == 0 { return }
        switch op {
        case 0x01: drawn = true
        case 0x02:
            drawn = false
            deck = nil
            flags = []
            beat = 0
            needle = nil
            meter = nil
            phase = DrawnPhase.unknown
        case 0x03:
            guard args[0] >= 1, args[0] <= 4, args[1] <= 1, args[3] <= 1, args[5] <= 1,
                  let player = DrawnDisplay.Player(rawValue: args[7]) else { return }
            guard drawn else { return }
            let new = Deck(number: Int(args[0]),
                           color: [Int(args[1]) << 7 | Int(args[2]), Int(args[3]) << 7 | Int(args[4]), Int(args[5]) << 7 | Int(args[6])],
                           player: player)
            guard new != deck else { return }
            deck = new
            // A new deck's play flags, texts, tempo and phase wait for its own messages; only feedback stale carries over.
            flags = flags.intersection(.stale)
            texts = [:]
            tempo = 0
            textHeard = false
            phase = DrawnPhase.unknown
        case 0x05: if drawn { tempo = word() }
        case 0x07:
            guard args[0] & 0x40 == 0 else { return }
            if drawn { flags = DrawnDisplay.State(rawValue: args[0]) }
        case 0x08:
            guard args[0] <= 4 else { return }
            if drawn { beat = Int(args[0]) }
        case 0x09: if drawn { needle = word() }
        case 0x0A: if drawn { meter = (Int(args[0]), Int(args[1])) }
        case 0x0B: if drawn { phase = word() >= 8192 ? word() - 16384 : word() }
        default: break
        }
    }

    /// A text message's characters as Windows-1252 codes; nil if malformed: a code below 0x20, an escape with nothing
    /// after it, or one of the undefined codes other than 0x81 (the box).
    private static func decode(_ chars: ArraySlice<UInt8>) -> [UInt8]? {
        var codes: [UInt8] = []
        var iterator = chars.makeIterator()
        while let char = iterator.next() {
            if char == 0x7F {
                guard let next = iterator.next() else { return nil }
                let code = 0x80 | next
                if [0x8D, 0x8F, 0x90, 0x9D].contains(code) { return nil }
                codes.append(code)
            } else if char < 0x20 {
                return nil
            } else {
                codes.append(char)
            }
        }
        return codes
    }

    public static func == (a: DrawnDisplayState, b: DrawnDisplayState) -> Bool {
        a.drawn == b.drawn && a.deck == b.deck && a.flags == b.flags && a.beat == b.beat && a.needle == b.needle
            && a.meterValue == b.meterValue && a.texts == b.texts && a.textHeard == b.textHeard && a.tempo == b.tempo
            && a.phase == b.phase
    }
}
