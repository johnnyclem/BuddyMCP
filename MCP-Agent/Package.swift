// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BuddyMCP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BuddyMCP",
            targets: ["BuddyMCP"]),
    ],
    targets: [
        .executableTarget(
            name: "BuddyMCP",
            dependencies: [],
            path: ".",
            exclude: ["AgentCore"], // Exclude Python code from Swift build
            sources: ["App", "Agent"]
        ),
    ]
)
