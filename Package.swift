// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Moor",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MoorShared"),
        .target(name: "MoorCore"),
        .executableTarget(
            name: "Moor",
            dependencies: ["MoorCore", "MoorShared"]
        ),
        .testTarget(
            name: "MoorCoreTests",
            dependencies: ["MoorCore"]
        ),
    ]
)
