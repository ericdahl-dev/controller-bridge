// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LC6000Kit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LC6000Core", targets: ["LC6000Core"]),
    ],
    targets: [
        // All bridge logic: the Coordinator, the Bridge, the mapping and the OSC codec.
        // Pure Swift: no CoreMIDI, no Network framework, no UI.
        .target(name: "LC6000Core", resources: [.copy("Resources/default_mapping.json")]),
        .testTarget(name: "LC6000CoreTests", dependencies: ["LC6000Core"]),
    ]
)
