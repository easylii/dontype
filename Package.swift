// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiYu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SiYu",
            path: "Sources/SiYu"
        )
    ]
)
