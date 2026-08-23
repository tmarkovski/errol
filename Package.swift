// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BotBridge",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BotBridge",
            path: "Sources/BotBridge"
        )
    ]
)
