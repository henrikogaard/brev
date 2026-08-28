// swift-tools-version: 5.10
//
// BrevAvatars — sender avatar resolution cascade.
//
// See ADR-0003. All external avatar lookups are off-by-default and
// gated by user opt-in (ADR-0006).

import PackageDescription

let package = Package(
    name: "BrevAvatars",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevAvatars", targets: ["BrevAvatars"])
    ],
    dependencies: [
        .package(path: "../BrevThemes")
    ],
    targets: [
        .target(
            name: "BrevAvatars",
            dependencies: [
                .product(name: "BrevThemes", package: "BrevThemes")
            ],
            path: "Sources/BrevAvatars",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BrevAvatarsTests",
            dependencies: ["BrevAvatars"],
            path: "Tests/BrevAvatarsTests"
        )
    ]
)
