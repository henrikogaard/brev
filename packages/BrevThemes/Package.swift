// swift-tools-version: 5.10
//
// BrevThemes — theme engine and the bundled built-in themes.
//
// See ADR-0002 (theme system). Themes are JSON in `themes/` at the
// repo root; this package wires the parsing, palette types, and the
// `@Environment(\.brevTheme)` injection.

import PackageDescription

let package = Package(
    name: "BrevThemes",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevThemes", targets: ["BrevThemes"])
    ],
    targets: [
        .target(
            name: "BrevThemes",
            path: "Sources/BrevThemes"
        ),
        .testTarget(
            name: "BrevThemesTests",
            dependencies: ["BrevThemes"],
            path: "Tests/BrevThemesTests"
        )
    ]
)
