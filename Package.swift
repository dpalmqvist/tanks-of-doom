// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TanksOfDoom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TanksCore"),
        .executableTarget(name: "TanksOfDoom", dependencies: [
            "TanksCore",
            .target(name: "LinuxSpriteKit", condition: .when(platforms: [.linux])),
        ]),
        .testTarget(name: "TanksCoreTests", dependencies: ["TanksCore"]),

        // Linux only: the subset of SpriteKit (plus a few AppKit and Core Graphics types) the game uses,
        // implemented on SDL2. On macOS this module compiles to nothing and the game uses SpriteKit.
        .target(name: "LinuxSpriteKit", dependencies: [
            .target(name: "CSDL2", condition: .when(platforms: [.linux])),
        ]),
        .systemLibrary(name: "CSDL2", pkgConfig: "sdl2", providers: [
            .apt(["libsdl2-dev", "libsdl2-ttf-dev"]),
            .yum(["SDL2-devel", "SDL2_ttf-devel"]),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
