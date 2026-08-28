// swift-tools-version: 5.10
//
// BrevMail — composite mail UI (folder sidebar, message list, reading
// pane, compose, search). Sits one rung above the design / theme /
// backend primitives; the only consumers are `apps/iOS` and
// `apps/macOS`. See ADR-0011.

import PackageDescription

let package = Package(
    name: "BrevMail",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevMail", targets: ["BrevMail"])
    ],
    dependencies: [
        .package(path: "../BrevBackend"),
        .package(path: "../BrevCrypto"),
        .package(path: "../BrevDesign"),
        .package(path: "../BrevPlugins"),
        .package(path: "../BrevSettings"),
        .package(path: "../BrevThemes"),
        .package(path: "../BrevAvatars"),
        .package(path: "../BrevCalendar"),
        .package(path: "../BrevAI"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "BrevMail",
            dependencies: [
                "BrevBackend",
                "BrevCrypto",
                "BrevDesign",
                "BrevPlugins",
                "BrevSettings",
                "BrevThemes",
                "BrevAvatars",
                "BrevCalendar",
                "BrevAI"
            ],
            path: "Sources/BrevMail",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevMailTests",
            dependencies: [
                "BrevMail",
                "BrevBackend",
                "BrevAI",
                "BrevThemes",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/BrevMailTests",
            exclude: ["__Snapshots__"]
        )
    ]
)
