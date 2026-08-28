// swift-tools-version: 5.10
//
// BrevAI — the `AIBackend` protocol and concrete backends.
//
// See ADR-0008. AI is always user-initiated (invariant 6 in ADR-0028);
// no code path in BrevAI sends content without explicit user action.

import PackageDescription

let package = Package(
    name: "BrevAI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevAI", targets: ["BrevAI"])
    ],
    targets: [
        .target(
            name: "BrevAI",
            path: "Sources/BrevAI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevAITests",
            dependencies: ["BrevAI"],
            path: "Tests/BrevAITests"
        )
    ]
)
