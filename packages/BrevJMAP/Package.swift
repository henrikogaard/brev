// swift-tools-version: 5.10
//
// BrevJMAP — Native RFC 8620 / RFC 8621 JMAP mail backend and session transport.

import PackageDescription

let package = Package(
    name: "BrevJMAP",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevJMAP", targets: ["BrevJMAP"])
    ],
    dependencies: [
        .package(path: "../BrevBackend")
    ],
    targets: [
        .target(
            name: "BrevJMAP",
            dependencies: ["BrevBackend"],
            path: "Sources/BrevJMAP",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevJMAPTests",
            dependencies: ["BrevJMAP", "BrevBackend"],
            path: "Tests/BrevJMAPTests"
        )
    ]
)
