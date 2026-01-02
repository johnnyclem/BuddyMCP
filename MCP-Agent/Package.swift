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
            exclude: [
                "AgentCore",        // Exclude Python code from Swift build
                "BuddyMCP.app",     // Exclude built app bundle
                "package_app.sh",   // Exclude packaging script
                "agent_core.log",   // Exclude runtime logs
                "AI_DOCS"           // Exclude AI documentation
            ],
            sources: ["App", "Agent"]
        ),
    ]
)
