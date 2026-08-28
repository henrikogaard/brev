// swift-tools-version: 5.10
//
// BrevDesign — Brev's design system: tokens, primitives, components.
//
// See ADR-0004 (build layout) and ADR-0002 (theme system). This package
// is consumed by both `apps/macOS` and `apps/iOS`; platform-specific
// behavior is expressed via SwiftUI conditional modifiers, never by
// duplicating components per platform.

import PackageDescription

let package = Package(
    name: "BrevDesign",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevDesign", targets: ["BrevDesign"])
    ],
    dependencies: [
        .package(path: "../BrevThemes"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "BrevDesign",
            dependencies: ["BrevThemes"],
            path: "Sources/BrevDesign",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevDesignTests",
            dependencies: [
                "BrevDesign",
                "BrevThemes",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/BrevDesignTests"
        )
    ]
)
