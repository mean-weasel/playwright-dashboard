// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlaywrightDashboard",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "PlaywrightDashboard",
            path: "Sources/PlaywrightDashboard"
        )
    ]
)
