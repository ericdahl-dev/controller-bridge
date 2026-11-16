extension CapturePorts {
    /// The ports to capture when the owner picks the source `picked`: it, then the device's other sources (named
    /// `picked` plus a word, like the LC6000's "WD" port), and the output of the same name, or else its other outputs.
    public static func suggested(for picked: String, sources: [String], destinations: [String]) -> CapturePorts {
        func sameDevice(_ name: String) -> Bool { name.hasPrefix(picked + " ") }
        let outputs = destinations.contains(picked) ? [picked] : destinations.filter(sameDevice)
        return CapturePorts(input: [picked] + sources.filter(sameDevice), output: outputs)
    }
}
