/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import ProjectDescription

let project = Project(
    name: "BrevSettingsSnapshots",
    organizationName: "Brev",
    options: .options(disableBundleAccessors: true, disableSynthesizedResourceAccessors: true),
    packages: [
        .package(path: "../../packages/BrevSettings"),
        .package(path: "../../packages/BrevBackend"),
        .package(path: "../../packages/BrevCalendar"),
        .package(path: "../../packages/BrevThemes"),
        .remote(url: "https://github.com/pointfreeco/swift-snapshot-testing", requirement: .exact("1.19.7"))
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "5.10",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "CODE_SIGNING_ALLOWED": "NO",
        "TARGETED_DEVICE_FAMILY": "1"
    ]),
    targets: [
        .target(
            name: "BrevSettingsSnapshotHost",
            destinations: [.iPhone],
            product: .app,
            bundleId: "eu.brevmail.brev.settings-snapshots",
            deploymentTargets: .iOS("26.5"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Settings Snapshots",
                "UILaunchScreen": [:],
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                    "UISceneConfigurations": [:]
                ]
            ]),
            sources: ["Sources/**"],
            resources: ["../iOS/Resources/Assets.xcassets"],
            dependencies: [
                .package(product: "BrevSettings"),
                .package(product: "BrevBackend"),
                .package(product: "BrevCalendar"),
                .package(product: "BrevThemes")
            ]
        ),
        .target(
            name: "BrevSettingsSnapshotTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "eu.brevmail.brev.settings-snapshots.tests",
            deploymentTargets: .iOS("26.5"),
            infoPlist: .default,
            sources: [
                "Tests/**",
                "../../packages/BrevSettings/Tests/BrevSettingsTests/SettingsFormSnapshotTests.swift"
            ],
            dependencies: [
                .target(name: "BrevSettingsSnapshotHost"),
                .package(product: "BrevSettings"),
                .package(product: "BrevBackend"),
                .package(product: "BrevCalendar"),
                .package(product: "BrevThemes"),
                .package(product: "SnapshotTesting")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "BrevSettingsSnapshots",
            shared: true,
            buildAction: .buildAction(targets: ["BrevSettingsSnapshotHost"]),
            testAction: .targets(["BrevSettingsSnapshotTests"]),
            runAction: .runAction(configuration: "Debug", executable: "BrevSettingsSnapshotHost")
        )
    ]
)
