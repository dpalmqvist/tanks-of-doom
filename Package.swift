// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TanksCore"),
        .target(name: "TanksNet", dependencies: ["TanksCore"]),
        .executableTarget(name: "TanksOfDoom", dependencies: ["TanksCore", "TanksNet"]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
        .testTarget(name: "TanksNetTests", dependencies: ["TanksNet", "TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
