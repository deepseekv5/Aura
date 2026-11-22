// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIRoleSim",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "AIRoleSim",
            path: "Sources/AIRoleSim"
        )
    ]
)
