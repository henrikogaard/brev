// swift-tools-version: 5.9
//
// Tuist/Package.swift — external SPM dependencies for the Brev workspace.

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "Sparkle": .framework
    ]
)
#endif

let package = Package(
    name: "BrevDependencies",
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMajor(from: "2.9.2"))
    ]
)
