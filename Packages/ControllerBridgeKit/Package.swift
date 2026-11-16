// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ControllerBridgeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ControllerBridgeCore", targets: ["ControllerBridgeCore"]),
        .library(name: "ControllerBridgePresentation", targets: ["ControllerBridgePresentation"]),
    ],
    targets: [
        // All bridge logic: the Coordinator, the Bridge, the mapping and the OSC codec.
        // Pure Swift: no CoreMIDI, no Network framework, no UI.
        .target(name: "ControllerBridgeCore", resources: [.copy("Resources/Profiles")]),
        // Resources holds test-only profiles, such as a second controller that ships in no app.
        .testTarget(name: "ControllerBridgeCoreTests", dependencies: ["ControllerBridgeCore"], resources: [.copy("Resources")]),
        // What the UI shows, as plain values: colors, contrast, deck badges and status words. No SwiftUI, so the
        // logic behind the look is tested here; the views themselves are checked by screenshot (#34).
        .target(name: "ControllerBridgePresentation"),
        // Core only for the test that pins the deck badges to Core's deck colors (#122); the targets stay independent.
        .testTarget(name: "ControllerBridgePresentationTests", dependencies: ["ControllerBridgePresentation", "ControllerBridgeCore"]),
    ]
)
