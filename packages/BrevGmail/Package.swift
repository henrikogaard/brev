// swift-tools-version: 5.10
//
// BrevGmail — Gmail API transport and provider models.
//
// See ADR-0064. Transport models stay local to this package; its only shared
// dependency is the provider-neutral fallback-error marker from BrevBackend.

import PackageDescription

let package = Package(
    name: "BrevGmail",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevGmail", targets: ["BrevGmail"])
    ],
    dependencies: [
        .package(path: "../BrevBackend")
    ],
    targets: [
        .target(
            name: "BrevGmail",
            dependencies: ["BrevBackend"],
            path: "Sources/BrevGmail",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "BrevGmailTests",
            dependencies: ["BrevGmail"],
            path: "Tests/BrevGmailTests"
        )
    ]
)
