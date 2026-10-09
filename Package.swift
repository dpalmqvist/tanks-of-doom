// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Used only by the relay server; the game itself has no third-party dependencies.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(name: "TanksCore"),
        .target(name: "TanksNet", dependencies: ["TanksCore"]),
        .executableTarget(name: "TanksOfDoom", dependencies: ["TanksCore", "TanksNet"]),
        .target(name: "TanksRelayCore", dependencies: [
            "TanksNet",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
        ]),
        .executableTarget(name: "TanksRelay", dependencies: ["TanksRelayCore", "TanksNet"]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),
        .testTarget(name: "TanksNetTests", dependencies: ["TanksNet", "TanksCore"]),
        .testTarget(name: "TanksRelayCoreTests", dependencies: ["TanksRelayCore", "TanksNet", "TanksCore"]),
    ],
    swiftLanguageModes: [.v5]
)
