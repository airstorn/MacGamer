// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGamer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
        .executable(name: "macgamer", targets: ["macgamer"]),
        .executable(name: "MacGamerApp", targets: ["MacGamerApp"])
    ],
    targets: [
        .target(
            name: "LauncherCore",
            resources: [
                .process("Resources"),
                .copy("BundledRuntime/winecx-26.2-osx64.tar.xz")
            ]
        ),
        .executableTarget(
            name: "macgamer",
            dependencies: ["LauncherCore"]
        ),
        .executableTarget(
            name: "MacGamerApp",
            dependencies: ["LauncherCore"]
        ),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
