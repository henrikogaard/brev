// swift-tools-version: 5.10
//
// BrevSyncEngine — folder-wide IMAP sync and cache engine (ADR-0030).
//
// This package owns the persistent SQLite index for IMAP message headers and
// bodies, the two-tier sync protocol (CONDSTORE / UID-scan), and the folder
// priority scheduler. It depends on BrevBackend for value types (MessageHeader,
// Folder, BrevAccount, MailEvent) but is never imported by BrevBackend itself,
// enforcing the one-way dependency direction described in ADR-0030.

import PackageDescription

let package = Package(
    name: "BrevSyncEngine",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevSyncEngine", targets: ["BrevSyncEngine"])
    ],
    dependencies: [
        .package(path: "../BrevBackend")
    ],
    targets: [
        .target(
            name: "BrevSyncEngine",
            dependencies: ["BrevBackend"],
            path: "Sources/BrevSyncEngine",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BrevSyncEngineTests",
            dependencies: ["BrevSyncEngine"],
            path: "Tests/BrevSyncEngineTests"
        )
    ]
)
