// swift-tools-version: 5.10
//
// BrevCrypto — message crypto processing adapters for Brev.
//
// Concrete implementations conform to `CryptoBodyProcessing` from
// `BrevBackend` and are consumed by `BrevMail`'s `BodyRenderer`.

import PackageDescription

let package = Package(
    name: "BrevCrypto",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "BrevCrypto", targets: ["BrevCrypto"])
    ],
    dependencies: [
        .package(path: "../BrevBackend")
    ],
    targets: [
        .target(
            name: "BrevCrypto",
            dependencies: [
                "BrevBackend"
            ],
            path: "Sources/BrevCrypto",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BrevCryptoTests",
            dependencies: [
                "BrevCrypto",
                "BrevBackend"
            ],
            path: "Tests/BrevCryptoTests"
        )
    ]
)
