import DeviceFinder

/// One section of the app, as the owner reads it.
public struct Section: Sendable, Equatable {
    public let status: String
    public let detail: String?

    init(status: String, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

/// The app's two sections (#685).
public struct UpdaterScreen: Sendable, Equatable {
    public let panel: Section
    public let lc6000: Section

    public init(found: Found, lc6000WarningAccepted: Bool) {
        switch found.panel {
        case nil: panel = Section(status: "Nothing connected")
        case .driverMissing: panel = Section(status: "Deck panel found", detail: "The USB driver for its chip is missing")
        case .onSerial(let build?): panel = Section(status: "Deck panel found", detail: "Build \(build.sha)")
        case .onSerial(nil): panel = Section(status: "Deck panel found")
        }
        lc6000 = Section(status: "Nothing connected")
    }
}
