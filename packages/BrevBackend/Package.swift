// swift-tools-version: 5.10
//
// BrevBackend — the provider-neutral abstraction the view layer talks to.
//
// See ADR-0001 (backend abstraction) and ADR-0028 invariant 2.
//
// Deliberately depends on nothing but Foundation: this package is the
// pinch point where view code (apps/*, packages/BrevDesign) stays
// independent of concrete mail-engine implementations. The backend
// implementations live outside this package so it can build cleanly
// on macOS too (ADR-0066).

import PackageDescription

let package = Package(
    name: "BrevBackend",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevBackend", targets: ["BrevBackend"])
    ],
    targets: [
        .target(
            name: "BrevBackend",
            path: "Sources/BrevBackend",
            resources: [.process("Resources")],
            // Network.framework is used only by NWConnectionSocketTransport.swift.
            // OSLog is used for local-only diagnostics/signposts; no telemetry
            // SDKs or automatic uploads are linked.
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .testTarget(
            name: "BrevBackendTests",
            dependencies: ["BrevBackend"],
            path: "Tests/BrevBackendTests"
        )
    ]
)
