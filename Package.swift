// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiYu",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CrashGuard",
            path: "Sources/CrashGuard"
        ),
        .executableTarget(
            name: "SiYu",
            dependencies: ["CrashGuard"],
            path: "Sources/SiYu"
        )
    ]
)
