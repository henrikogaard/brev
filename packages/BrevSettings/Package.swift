// swift-tools-version: 5.10
//
// BrevSettings — settings surface (accounts, appearance, signature,
// about). One rung above the primitives; the only consumers are
// `apps/iOS` and `apps/macOS`. See ADR-0012.

import PackageDescription

let package = Package(
    name: "BrevSettings",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevSettings", targets: ["BrevSettings"])
    ],
    dependencies: [
        .package(path: "../BrevAI"),
        .package(path: "../BrevAvatars"),
        .package(path: "../BrevBackend"),
        .package(path: "../BrevCalendar"),
        .package(path: "../BrevDesign"),
        .package(path: "../BrevPlugins"),
        .package(path: "../BrevThemes"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "BrevSettings",
            dependencies: ["BrevAI", "BrevAvatars", "BrevBackend", "BrevCalendar", "BrevDesign", "BrevPlugins", "BrevThemes"],
            path: "Sources/BrevSettings",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevSettingsTests",
            dependencies: [
                "BrevSettings",
                "BrevAI",
                "BrevAvatars",
                "BrevBackend",
                "BrevThemes",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/BrevSettingsTests",
            exclude: ["__Snapshots__"]
        )
    ]
)
