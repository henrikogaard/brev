// swift-tools-version: 5.10
//
// BrevCalendar — ICS handling shell for v1, calendar primitives for v2.
//
// See ADR-0007. v1 surface is intentionally narrow (parse + display the
// provider-resolved invite); local ICS parsing for mail backends
// arrives in v2.

import PackageDescription

let package = Package(
    name: "BrevCalendar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevCalendar", targets: ["BrevCalendar"])
    ],
    targets: [
        .target(
            name: "BrevCalendar",
            path: "Sources/BrevCalendar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevCalendarTests",
            dependencies: ["BrevCalendar"],
            path: "Tests/BrevCalendarTests"
        )
    ]
)
