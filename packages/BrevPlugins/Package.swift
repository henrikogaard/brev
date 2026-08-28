// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrevPlugins",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevPlugins", targets: ["BrevPlugins"])
    ],
    targets: [
        .target(
            name: "BrevPlugins",
            path: "Sources/BrevPlugins"
        ),
        .testTarget(
            name: "BrevPluginsTests",
            dependencies: ["BrevPlugins"],
            path: "Tests/BrevPluginsTests"
        )
    ]
)
