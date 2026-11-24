// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicIsland",
            dependencies: [],
            path: ".",
            exclude: [
                "Tests",
                "scripts",
                "DynamicIsland.app",
                "README.md",
                "README.en.md",
                "LICENSE",
                "AGENTS.md",
                ".gitignore",
                ".claudeignore"
            ],
            sources: ["Sources/DynamicIsland"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DynamicIslandTests",
            dependencies: ["DynamicIsland"],
            path: "Tests/DynamicIslandTests"
        )
    ]
)
