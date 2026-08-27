// swift-tools-version: 5.9
//
// The package builds the app's detection/relay engine (the same files the
// Xcode app target compiles — Sources live in app/Errol/Errol/Core, pointed
// at in place) as the ErrolKit library, plus the tools that reuse it:
//
//   swift test               # contract tests for the pure detection logic
//   tools/verify [...]       # the guided live harness (see tools/verify.swift)
//
// The Xcode app does NOT depend on this package; it keeps compiling Core
// directly. The package exists so tools and tests consume the identical
// sources — one set of files, two build paths, no copies to drift. The
// harness and tests use `@testable import ErrolKit` (debug builds enable
// testability), so Core needs no public annotations.

import PackageDescription

let package = Package(
    name: "Errol",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ErrolKit",
            path: "app/Errol/Errol/Core"),
        .executableTarget(
            name: "errol-verify",
            dependencies: ["ErrolKit"],
            path: "tools/errol-verify"),
        .testTarget(
            name: "ErrolKitTests",
            dependencies: ["ErrolKit"],
            path: "tests/ErrolKitTests",
            resources: [.copy("Fixtures")]),
    ]
)
