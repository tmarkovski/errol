// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Errol",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Errol",
            path: "Sources/Errol"
        )
    ]
)
