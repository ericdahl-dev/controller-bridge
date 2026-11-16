/// A control held down in Syndicate: what to send to let it go.
///
/// Recorded at press time with the deck and full address, so a release always reaches the deck that got the press,
/// even if the controller's deck changes in between.
struct HeldControl: Equatable {
    var deck: Int
    var address: String
    var release: [OSCArgument]
}

/// The controls that need a release.
enum HoldKey: Hashable {
    case cue
    case censor
    case pad(Int)
    case bend
    case phaseMinus
    case phasePlus
}

/// The held controls, in press order.
struct HeldControls {
    private var keys: [HoldKey] = []
    private var controls: [HoldKey: HeldControl] = [:]

    mutating func record(_ key: HoldKey, _ control: HeldControl) {
        if controls[key] == nil { keys.append(key) }
        controls[key] = control
    }

    /// Whether the control is held now.
    func contains(_ key: HoldKey) -> Bool {
        controls[key] != nil
    }

    /// Forgets the control and returns what to send to release it, or nil if it isn't held.
    mutating func take(_ key: HoldKey) -> HeldControl? {
        guard let control = controls.removeValue(forKey: key) else { return nil }
        keys.removeAll { $0 == key }
        return control
    }

    /// Forgets every control and returns their releases, in press order.
    mutating func takeAll() -> [HeldControl] {
        defer { keys.removeAll(); controls.removeAll() }
        return keys.compactMap { controls[$0] }
    }
}
