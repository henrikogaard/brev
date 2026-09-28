// swift-tools-version: 5.10
//
// BrevWidgets — the shared snapshot schema and the WidgetKit surfaces.
//
// See ADR-0083. The widget extension renders a `WidgetSnapshot.json`
// file the app writes into the shared App Group container; the
// extension links nothing else — no BrevBackend, no Realm, no network.

import PackageDescription

let package = Package(
    name: "BrevWidgets",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevWidgets", targets: ["BrevWidgets"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "BrevWidgets",
            dependencies: [],
            path: "Sources/BrevWidgets",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevWidgetsTests",
            dependencies: [
                "BrevWidgets",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/BrevWidgetsTests"
        )
    ]
)
