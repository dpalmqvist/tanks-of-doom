// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TanksCore"),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
