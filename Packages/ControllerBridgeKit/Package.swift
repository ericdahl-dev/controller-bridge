// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ControllerBridgeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ControllerBridgeCore", targets: ["ControllerBridgeCore"]),
    ],
    targets: [
        // All bridge logic: the Coordinator, the Bridge, the mapping and the OSC codec.
        // Pure Swift: no CoreMIDI, no Network framework, no UI.
        .target(name: "ControllerBridgeCore", resources: [.copy("Resources/Profiles")]),
        .testTarget(name: "ControllerBridgeCoreTests", dependencies: ["ControllerBridgeCore"]),
    ]
)
