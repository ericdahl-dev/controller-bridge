// swift-tools-version: 6.2
import PackageDescription

// The firmware updater (spec #684): a separate Mac app, sharing nothing at runtime with DeckBridge.
let package = Package(
    name: "FirmwareUpdaterKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "FirmwareModel", targets: ["FirmwareModel"]),
        .library(name: "FirmwareCatalog", targets: ["FirmwareCatalog"]),
    ],
    targets: [
        // Plain values the device finder and the catalog share: what was found, and how versions compare. No logic
        // beyond comparing, so the finder never sees the catalog and the catalog never touches a device.
        .target(name: "FirmwareModel"),
        // The firmware the app ships with (#686): the deck panel image and the LC6000 patch descriptions, with the
        // rules for what applies to what. Built-in resources only; no network.
        .target(name: "FirmwareCatalog", dependencies: ["FirmwareModel"], resources: [.copy("Catalog")]),
        .testTarget(name: "FirmwareCatalogTests", dependencies: ["FirmwareCatalog", "FirmwareModel"], resources: [.copy("Fixtures")]),
    ]
)
