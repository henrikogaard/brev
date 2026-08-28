// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrevExamplePlugin",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevExamplePlugin", targets: ["BrevExamplePlugin"])
    ],
    dependencies: [
        .package(path: "../../packages/BrevPlugins")
    ],
    targets: [
        .target(
            name: "BrevExamplePlugin",
            dependencies: ["BrevPlugins"],
            path: "Sources/BrevExamplePlugin",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevExamplePluginTests",
            dependencies: ["BrevExamplePlugin", "BrevPlugins"],
            path: "Tests/BrevExamplePluginTests"
        )
    ]
)
