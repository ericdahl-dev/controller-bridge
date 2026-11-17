import Foundation

extension Mapping {
    /// Every problem in a mapping body (a whole mapping, or a partial one to merge over the default), named by key
    /// path, in document order (#24). The bundled default mapping is the schema. An empty list means it's usable.
    /// `whole`: the mapping of a whole profile file (#251), checked for duplicates against its own keys only, not merged
    /// over the LC6000's, so a second controller doesn't collide with LC6000 buttons it doesn't have.
    public static func problems(in json: Data, whole: Bool = false) -> [String] {
        do {
            return problems(in: try OrderedJSON(parsing: json), whole: whole)
        } catch {
            return ["\(error)"]
        }
    }

    /// `schema` is the body of the profile being changed (#94); by default the bundled LC6000's.
    static func problems(in document: OrderedJSON, schema given: OrderedJSON? = nil, whole: Bool = false) -> [String] {
        guard let schema = given ?? (try? OrderedJSON(parsing: defaultJSON())) else { return ["The default mapping can't be read."] }
        if let problem = kindProblem(document, expected: schema) { return ["mapping: \(problem)"] }
        var out: [String] = []
        walk(document, schema: schema, path: "", into: &out)
        let checked = known(document, schema: schema)
        out += duplicates(in: whole ? checked : merge(schema, checked), written: Set(leafPaths(document)))
        // Document order: by where the problem's path first appears in what the user wrote.
        let order = Dictionary(leafPaths(document).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return out.enumerated().sorted { a, b in
            let (pa, pb) = (order[path(of: a.element)] ?? Int.max, order[path(of: b.element)] ?? Int.max)
            return pa == pb ? a.offset < b.offset : pa < pb
        }.map(\.element)
    }

    private static func path(of problem: String) -> String { String(problem.prefix { $0 != ":" }) }

    /// Every path in a document, objects and lists included, in document order.
    private static func leafPaths(_ value: OrderedJSON, _ path: String = "") -> [String] {
        switch value {
        case .object(let pairs):
            return (path.isEmpty ? [] : [path]) + pairs.flatMap { leafPaths($0.value, path.isEmpty ? $0.key : "\(path).\($0.key)") }
        case .array(let items):
            return [path] + items.enumerated().flatMap { leafPaths($1, "\(path)[\($0)]") }
        default:
            return [path]
        }
    }

    /// The document without unknown keys or values of the wrong kind, already reported, so they can't also show
    /// up as duplicates.
    private static func known(_ value: OrderedJSON, schema: OrderedJSON, path: String = "") -> OrderedJSON {
        switch (value, schema) {
        case let (.object(pairs), .object):
            return .object(pairs.compactMap { pair in
                let childPath = path.isEmpty ? pair.key : "\(path).\(pair.key)"
                guard let given = schema[pair.key] ?? optionalKey(childPath) ?? shiftedSchema(childPath, notes: schema) else { return nil }
                let expected = alternative(pair.value, at: childPath) ?? given
                guard kindProblem(pair.value, expected: expected) == nil else { return nil }
                return (pair.key, known(pair.value, schema: expected, path: childPath))
            })
        case let (.array(items), .array(schemaItems)):
            guard let element = schemaItems.first else { return value }
            // Null, not dropped, so the other items keep their indices.
            return .array(items.map { kindProblem($0, expected: element) == nil ? $0 : .null })
        default:
            return value
        }
    }

    /// The Python merge on ordered JSON: objects merge key by key, keeping the base's order; anything else replaces.
    static func merge(_ base: OrderedJSON, _ override: OrderedJSON) -> OrderedJSON {
        guard case .object(var pairs) = base, case .object(let overrides) = override else { return override }
        for (key, value) in overrides {
            if let index = pairs.firstIndex(where: { $0.key == key }) {
                pairs[index].value = merge(pairs[index].value, value)
            } else {
                pairs.append((key, value))
            }
        }
        return .object(pairs)
    }

    /// Where each kind of MIDI number is used. Notes and CCs are separate namespaces; LED notes aren't checked, as
    /// an LED may share its button's note.
    private static func uses(_ merged: OrderedJSON) -> (notes: [(String, Double)], ccs: [(String, Double)]) {
        var notes: [(String, Double)] = [], ccs: [(String, Double)] = []
        for path in leafPaths(merged) {
            guard case .number(let n, _)? = value(at: path, in: merged) else { continue }
            let pattern = path.replacingOccurrences(of: #"\[\d+\]"#, with: "[]", options: .regularExpression)
            if pattern.hasPrefix("notes.") || pattern == "needle.touch_note" || mixerNotes.map({ "mixer.\($0)" }).contains(pattern) {
                notes.append((path, n))
            } else if ["jog.msb_cc", "jog.lsb_cc", "pitch.msb_cc", "pitch.lsb_cc", "needle.msb_cc", "needle.lsb_cc", "browse.select_turn_cc",
                       "browse.auto_loop_size_cc", "jog.relative_cc", "jog.relative_edge_cc"].contains(pattern)
                // A mixer fader's CCs are inputs too; the meter's CC is an output, so it can't clash with one (#207).
                || mixerControls.contains(where: { pattern == "mixer.\($0).msb_cc" || pattern == "mixer.\($0).lsb_cc" }) {
                ccs.append((path, n))
            }
        }
        return (notes, ccs)
    }

    /// A number used twice in one namespace, reported at the path the user wrote (the later one if they wrote both).
    private static func duplicates(in merged: OrderedJSON, written: Set<String>) -> [String] {
        let (notes, ccs) = uses(merged)
        let (deck, pads) = channels(merged)
        // A note can arrive on the pads' channels or the deck's (#251): two notes collide only where those meet.
        let noteChannels = notes.map { (path: $0.0, n: $0.1, channels: $0.0.hasPrefix("notes.pads[") ? pads : deck) }
        let anyChannel = ccs.map { (path: $0.0, n: $0.1, channels: deck) }
        let layers = layerChannels(merged).map { (path: $0.0, n: $0.1, channels: Set([0.0])) }
        var out: [String] = []
        for (kind, list) in [("note", noteChannels), ("CC", anyChannel), ("channel", layers)] {
            var groups: [(n: Double, channels: Set<Double>, paths: [String])] = []
            for use in list {
                if let index = groups.firstIndex(where: { $0.n == use.n && !$0.channels.isDisjoint(with: use.channels) }) {
                    groups[index].paths.append(use.path)
                    groups[index].channels.formUnion(use.channels)
                } else {
                    groups.append((use.n, use.channels, [use.path]))
                }
            }
            for group in groups where group.paths.count > 1 {
                guard let at = group.paths.last(where: written.contains) else { continue }
                let others = group.paths.filter { $0 != at }.joined(separator: " and ")
                out.append("\(at): \(kind) \(Int(group.n)) is also \(others)")
            }
        }
        return out
    }

    /// The channels the deck's buttons arrive on (midi.channel and every layer's) and the pads' (pads.channel, or each
    /// layer's pad_channel, else the deck's) (#224, #251).
    private static func channels(_ merged: OrderedJSON) -> (deck: Set<Double>, pads: Set<Double>) {
        func number(_ value: OrderedJSON?) -> Double? { if case .number(let n, _)? = value { n } else { nil } }
        var deck = Set([number(merged["midi"]?["channel"]) ?? 1])
        var pads: Set<Double> = []
        let padChannel = number(merged["pads"]?["channel"])
        if case .array(let layers)? = merged["midi"]?["layers"], !layers.isEmpty {
            for layer in layers {
                guard let channel = number(layer["channel"]) else { continue }
                deck.insert(channel)
                pads.insert(number(layer["pad_channel"]) ?? padChannel ?? channel)
            }
        }
        if pads.isEmpty { pads = padChannel.map { [$0] } ?? deck }
        return (deck, pads)
    }

    /// Each layer's channel: two layers can't share one (#79).
    private static func layerChannels(_ merged: OrderedJSON) -> [(String, Double)] {
        guard case .array(let layers)? = merged["midi"]?["layers"] else { return [] }
        return layers.indices.compactMap { index in
            guard case .number(let channel, _)? = layers[index]["channel"] else { return nil }
            return ("midi.layers[\(index)].channel", channel)
        }
    }

    private static func value(at path: String, in document: OrderedJSON) -> OrderedJSON? {
        var current: OrderedJSON? = document
        for part in path.split(separator: ".") {
            var name = Substring(part)
            var indices: [Int] = []
            while let open = name.lastIndex(of: "["), name.hasSuffix("]") {
                indices.insert(Int(name[name.index(after: open)..<name.index(before: name.endIndex)])!, at: 0)
                name = name[..<open]
            }
            current = current?[String(name)]
            for i in indices {
                guard case .array(let items)? = current, items.indices.contains(i) else { return nil }
                current = items[i]
            }
        }
        return current
    }

    /// The default mapping body, the schema every import is checked against.
    public static func defaultMappingJSON() throws -> Data { try defaultJSON() }

    private static func walk(_ value: OrderedJSON, schema given: OrderedJSON, path: String, into out: inout [String]) {
        let schema = alternative(value, at: path) ?? given
        if let problem = kindProblem(value, expected: schema) {
            out.append("\(path): \(problem)")
            return
        }
        if let problem = valueProblem(value, at: path) {
            out.append("\(path): \(problem)")
            return
        }
        switch (value, schema) {
        case let (.object(pairs), _):
            for (key, child) in pairs {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                guard let expected = schema[key] ?? optionalKey(childPath) ?? shiftedSchema(childPath, notes: schema) else {
                    out.append("\(childPath): unknown key")
                    continue
                }
                walk(child, schema: expected, path: childPath, into: &out)
            }
        case let (.array(items), .array(schemaItems)):
            guard let element = schemaItems.first else { return }
            for (index, item) in items.enumerated() {
                walk(item, schema: element, path: "\(path)[\(index)]", into: &out)
            }
        default:
            break
        }
    }

    /// What's wrong with a value's kind, measured against the default's value at the same path; nil when it fits.
    static func kindProblem(_ value: OrderedJSON, expected: OrderedJSON) -> String? {
        let fits = switch (value, expected) {
        case (.object, .object), (.array, .array), (.string, .string), (.bool, .bool): true
        // A setting whose default is whole takes only whole numbers (2.0 is whole); a fractional one takes any.
        case let (.number(n, _), .number(_, isInteger)): !isInteger || n.rounded() == n
        default: false
        }
        guard !fits else { return nil }
        let wanted = switch expected {
        case .object: "an object"
        case .array: "a list"
        case .string: "text"
        case .bool: "true or false"
        case .number(_, let isInteger): isInteger ? "a whole number" : "a number"
        case .null: "nothing"
        }
        return "expected \(wanted), got \(describe(value))"
    }

    /// Keys that take another kind than the default's too, with an example of it: the color table is "rgb222" or a
    /// list of entries (#197).
    private static let alternatives: [String: OrderedJSON] = [
        "leds.color_table": .array([.object([("rgb", .array([.number(0, isInteger: true)])), ("value", .number(0, isInteger: true))])]),
    ]

    /// The alternative schema at `path` when the value is of its kind.
    private static func alternative(_ value: OrderedJSON, at path: String) -> OrderedJSON? {
        guard let other = alternatives[path], kindProblem(value, expected: other) == nil else { return nil }
        return other
    }

    /// Keys a profile may add that the LC6000's default leaves out (#204), with an example of each one's kind.
    /// `notes.shifted` (#226): the notes' own buttons, each a note, so a misspelled button is an unknown key and each
    /// note gets the notes' range and duplicate checks.
    private static func shiftedSchema(_ path: String, notes: OrderedJSON) -> OrderedJSON? {
        guard path == "notes.shifted", case .object(let pairs) = notes else { return nil }
        return .object(pairs.filter { $0.key != "pads" && $0.key != "shifted" })
    }

    /// The mixer's faders and knobs (#207), and every key the section takes.
    private static let mixerControls = ["volume", "trim", "eq_high", "eq_mid", "eq_low", "filter", "filter_res", "filter_width"]
    private static let mixerNotes = ["cue_note", "mute_note", "solo_note"]
    private static let mixerSchema: OrderedJSON = {
        let int = OrderedJSON.number(0, isInteger: true)
        let control = OrderedJSON.object([("msb_cc", int), ("lsb_cc", int), ("bits", int)])
        return .object(mixerControls.map { ($0, control) } + mixerNotes.map { ($0, int) } + [
            ("meter", .object([("cc", int), ("steps", .array([int])), ("clip", int), ("hold_ms", int), ("rate_hz", int)])),
            ("pickup", .bool(true)), ("pickup_tolerance", .number(0.02, isInteger: false)),
        ])
    }()

    private static let optionalKeys: [String: OrderedJSON] = [
        // The mixer section (#207): the LC6000 has none.
        "mixer": mixerSchema,
        "jog.relative_cc": .number(0, isInteger: true),
        "jog.relative_edge_cc": .number(0, isInteger: true),
        // One cycling pad-mode button (#198): its note, and its LED's velocity per mode.
        "notes.mode_cycle": .number(0, isInteger: true),
        "pads.mode_cycle_velocities": .object([
            ("hotcue", .number(0, isInteger: true)), ("roll", .number(0, isInteger: true)),
            ("loop", .number(0, isInteger: true)), ("slicer", .number(0, isInteger: true)),
        ]),
        // The pads' own MIDI channel (#224), for the deck and for each deck layer.
        "pads.channel": .number(0, isInteger: true),
        "midi.layers[].pad_channel": .number(0, isInteger: true),
        // Each pad mode's own notes (#225).
        "pads.mode_notes": .object([
            ("hotcue", .array([.number(0, isInteger: true)])), ("roll", .array([.number(0, isInteger: true)])),
            ("loop", .array([.number(0, isInteger: true)])), ("slicer", .array([.number(0, isInteger: true)])),
        ]),
    ]

    /// An optional key's expected kind by its path, a list element's index written as `[]`.
    private static func optionalKey(_ path: String) -> OrderedJSON? {
        optionalKeys[path.replacingOccurrences(of: #"\[\d+\]"#, with: "[]", options: .regularExpression)]
    }

    /// Ranges and choices, by key path. A list element's path ends in `[]`.
    private static let ranges: [String: ClosedRange<Double>] = {
        var table: [String: ClosedRange<Double>] = [
            "midi.channel": 1...16,
            "deck.number": 1...4,
            "midi.layers[].channel": 1...16,
            "midi.layers[].deck": 1...4,
            "midi.layers[].pad_channel": 1...16, "pads.channel": 1...16,
            "pads.mode_notes.hotcue[]": 0...127, "pads.mode_notes.roll[]": 0...127,
            "pads.mode_notes.loop[]": 0...127, "pads.mode_notes.slicer[]": 0...127,
            "midi.layer_note": 0...127,
            "notes.pads[]": 0...127,
            "jog.msb_cc": 0...127, "jog.lsb_cc": 0...127, "jog.relative_cc": 0...127, "jog.relative_edge_cc": 0...127,
            "pitch.msb_cc": 0...127, "pitch.lsb_cc": 0...127,
            "needle.msb_cc": 0...127, "needle.lsb_cc": 0...127, "needle.touch_note": 0...127,
            "midi.ignore_notes[]": 0...127,
            "browse.select_turn_cc": 0...127, "browse.auto_loop_size_cc": 0...127,
            "leds.pitch_center": 0...127, "leds.ring": 0...127,
            "leds.levels.full": 0...127, "leds.levels.dim": 0...127, "leds.levels.off": 0...127,
            "leds.color_table[].rgb[]": 0...255, "leds.color_table[].value": 0...127,
            "pads.mode_cycle_velocities.hotcue": 0...127, "pads.mode_cycle_velocities.roll": 0...127,
            "pads.mode_cycle_velocities.loop": 0...127, "pads.mode_cycle_velocities.slicer": 0...127,
            "jog.counts_per_rev": 1...16384, "jog.beats_per_rev": 1...16, "jog.seek_seconds_per_rev": 0...60,
            // Every other number, so no imported value can be absurd (#92).
            "osc.port": 1...65535, "osc.feedback_port": 1...65535,
            "osc.feedback_quiet_ms": 0...60000, "osc.feedback_answer_ms": 0...60000, "leds.pulse_ms": 0...60000,
            "jog.bend_release_ms": 1...5000,
            "pitch.dead_zone": 0...1, "pitch.pickup_tolerance": 0...1,
            "mixer.cue_note": 0...127, "mixer.mute_note": 0...127, "mixer.solo_note": 0...127,
            "mixer.meter.cc": 0...127, "mixer.meter.steps[]": 0...127, "mixer.meter.clip": 0...127,
            "mixer.meter.hold_ms": 0...10000, "mixer.meter.rate_hz": 1...120, "mixer.pickup_tolerance": 0...1,
        ]
        for control in mixerControls {
            table["mixer.\(control).msb_cc"] = 0...127
            table["mixer.\(control).lsb_cc"] = 0...127
        }
        for color in ["ring_color", "roll_pad_color", "loop_pad_color"] { table["leds.\(color)[]"] = 0...255 }
        return table
    }()

    private static let colors: Set<String> = ["leds.ring_color", "leds.roll_pad_color", "leds.loop_pad_color", "leds.color_table[].rgb"]

    /// Numbers that are one of a few values, not a range (#195).
    private static let numberChoices: [String: [Double]] = {
        var table: [String: [Double]] = ["pitch.bits": [7, 14]]
        for control in mixerControls { table["mixer.\(control).bits"] = [7, 14] }
        return table
    }()

    private static let choices: [String: [String]] = [
        "leds.beat_pulse": LEDs.BeatPulse.allRawValues,
        "leds.stale_idle": LEDs.StaleIdle.allRawValues,
        "pads.roll_sizes[]": Pads.RollSize.allRawValues,
        "pads.mode_select": Pads.ModeSelect.allRawValues,
        "midi.encoder_format": EncoderFormat.allRawValues,
        "leds.color_table": ["rgb222"],
    ]

    /// A range, count or choice problem with a value of the right kind; nil when it's fine.
    private static func valueProblem(_ value: OrderedJSON, at path: String) -> String? {
        let pattern = path.replacingOccurrences(of: #"\[\d+\]"#, with: "[]", options: .regularExpression)
        switch value {
        case .number(let n, _):
            // Every note is 0–127, whatever its button is called.
            if let allowed = numberChoices[pattern], !allowed.contains(n) {
                return "\(describe(value)) isn't one of \(allowed.map { String(Int($0)) }.joined(separator: ", "))"
            }
            let range = ranges[pattern] ?? (pattern.hasPrefix("notes.") ? 0...127 : nil)
            if let range, !range.contains(n) {
                return "\(describe(value)) is out of range, expected \(Int(range.lowerBound))-\(Int(range.upperBound))"
            }
        case .array(let items) where colors.contains(pattern) && items.count != 3:
            return "expected 3 values, got \(items.count)"
        case .array(let items) where pattern == "leds.color_table" && items.isEmpty:
            return "expected at least one entry"
        case .array(let items) where pattern == "mixer.meter.steps" && items.isEmpty:
            return "expected at least one value"
        case .array(let items) where pattern == "notes.pads" && !(1...16).contains(items.count):
            // 4, 8 or 16 pads, or anything between (#196).
            return "expected 1-16 pads, got \(items.count)"
        case .string(let text):
            if let allowed = choices[pattern], !allowed.contains(text) {
                return "\(describe(value)) isn't one of \(allowed.joined(separator: ", "))"
            }
        default:
            break
        }
        return nil
    }

    /// A value as the user wrote it, for a problem message.
    static func describe(_ value: OrderedJSON) -> String {
        switch value {
        case .object: "an object"
        case .array: "a list"
        case .string(let text): "\"\(text)\""
        case .bool(let flag): flag ? "true" : "false"
        case .null: "null"
        case .number(let n, _): n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        }
    }
}

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var allRawValues: [String] { allCases.map(\.rawValue) }
}
