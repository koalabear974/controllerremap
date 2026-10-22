// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ControllerRemap",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "ControllerRemap",
            path: "Sources/ControllerRemap"
        )
    ]
)
