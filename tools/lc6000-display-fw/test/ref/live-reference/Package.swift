// swift-tools-version: 6.2
// The drawn display firmware's reference tool for the live elements (#459): JogDisplayRenderer with a lit beat and a
// marker, as the Diagnostics simulator draws them. Kept here, beside the C tests that read its images.
import PackageDescription

let package = Package(
    name: "live-reference",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../../../../Packages/ControllerBridgeKit")],
    targets: [
        .executableTarget(name: "live-reference", dependencies: [
            .product(name: "ControllerBridgeRender", package: "ControllerBridgeKit"),
            .product(name: "ControllerBridgeCore", package: "ControllerBridgeKit"),
        ]),
    ]
)
