// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentGauge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentGaugeCore", targets: ["AgentGaugeCore"]),
        .executable(name: "AgentGaugeApp", targets: ["AgentGaugeApp"]),
        .executable(name: "AgentGaugeCleanup", targets: ["AgentGaugeCleanup"]),
        .executable(name: "AgentGaugeProbe", targets: ["AgentGaugeProbe"])
    ],
    targets: [
        .target(
            name: "CNativeDockTile",
            path: "Sources/CNativeDockTile",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AgentGaugeCore",
            dependencies: ["CNativeDockTile"],
            path: "Sources/AgentGaugeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "AgentGaugeApp",
            dependencies: ["AgentGaugeCore"],
            path: "Sources/AgentGaugeApp"
        ),
        .executableTarget(
            name: "AgentGaugeCleanup",
            dependencies: ["CNativeDockTile"],
            path: "Sources/AgentGaugeCleanup"
        ),
        .executableTarget(
            name: "AgentGaugeProbe",
            dependencies: ["AgentGaugeCore", "CNativeDockTile"],
            path: "Sources/AgentGaugeProbe"
        )
    ]
)
