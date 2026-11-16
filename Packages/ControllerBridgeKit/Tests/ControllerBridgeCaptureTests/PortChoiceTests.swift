import ControllerBridgeCapture
import Testing

/// Which ports a capture listens to (#186): the device the owner picked, plus its other ports, nothing else.
@Suite("Capture port choice")
struct PortChoiceTests {
    static let sources = ["IAC Driver Bus 1", "LC6000 PRIME", "LC6000 PRIME WD", "Launchpad X", "Launchpad X MIDI"]
    static let destinations = ["IAC Driver Bus 1", "LC6000 PRIME", "LC6000 PRIME WD", "Launchpad X"]

    @Test("Picking the LC6000 listens to its main and WD ports, and names its main output")
    func lc6000() {
        #expect(CapturePorts.suggested(for: "LC6000 PRIME", sources: Self.sources, destinations: Self.destinations)
            == CapturePorts(input: ["LC6000 PRIME", "LC6000 PRIME WD"], output: ["LC6000 PRIME"]))
    }

    @Test("A name that's only a prefix of another word isn't the same device; a device with no output names none")
    func unrelated() {
        #expect(CapturePorts.suggested(for: "Launchpad X", sources: Self.sources + ["Launchpad XL"], destinations: [])
            == CapturePorts(input: ["Launchpad X", "Launchpad X MIDI"], output: []))
    }

    @Test("The picked port comes first, whatever the system's order")
    func pickedFirst() {
        #expect(CapturePorts.suggested(for: "LC6000 PRIME WD", sources: Self.sources, destinations: Self.destinations).input
            == ["LC6000 PRIME WD"])
    }
}
