// swift-tools-version: 5.9
//
// A spike, not part of Errol: a broker that stands in for Errol, and a stdio
// MCP server that ChatGPT's Codex mode and Claude Code both start from one
// plugin. See README.md. It builds on its own and shares no sources with the
// app or with the root package.

import PackageDescription

let package = Package(
    name: "ErrolRelaySpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "errol-relay", path: "Sources/errol-relay"),
    ]
)
