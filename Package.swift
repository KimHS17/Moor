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
        // SMC 키 실측용 프로토타입 CLI. 앱·헬퍼와 의존 관계를 두지 않는다.
        .executableTarget(name: "MoorSMCProbe"),
        .testTarget(
            name: "MoorCoreTests",
            dependencies: ["MoorCore"]
        ),
        .testTarget(
            name: "MoorSMCProbeTests",
            dependencies: ["MoorSMCProbe"]
        ),
    ]
)
