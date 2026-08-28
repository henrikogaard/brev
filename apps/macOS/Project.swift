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
import ProjectDescriptionHelpers

// BrevMacOS — the macOS app target.
//
// Per ADR-0028 and ADR-0029, standards-first IMAP/SMTP account setup
// is the default shipping path. Native Gmail API accounts are added through
// the dedicated BrevGmail adapter; other providers remain IMAP/SMTP.
//
// Dependencies are intentionally limited to Brev-owned SPM packages,
// including the native Gmail API adapter, which build cleanly on macOS 14+.

let project = Project(
    name: "BrevMacOS",
    organizationName: "Brev",
    packages: [
        .package(path: "../../packages/BrevBackend"),
        .package(path: "../../packages/BrevGmail"),
        .package(path: "../../packages/BrevDesign"),
        .package(path: "../../packages/BrevMail"),
        .package(path: "../../packages/BrevPlugins"),
        .package(path: "../../packages/BrevSettings"),
        .package(path: "../../packages/BrevSyncEngine"),
        .package(path: "../../packages/BrevThemes"),
        .package(path: "../../Plugins/BrevExamplePlugin")
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": BrevConstants.swiftVersion,
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "MARKETING_VERSION": .string(BrevConstants.marketingVersion),
            "CURRENT_PROJECT_VERSION": .string(BrevConstants.buildNumber),
            "DEVELOPMENT_TEAM": .string(BrevConstants.teamID),
            "CODE_SIGN_STYLE": "Automatic",
            // Localization (ADR-0058): extract `String(localized:)` / SwiftUI
            // literals into the target's String Catalog on build.
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
            "BREV_SPARKLE_PUBLIC_ED_KEY": "BREV_SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER",
            // Public platform-specific OAuth values are injected into Info.plist.
            // The build environment supplies Google's non-confidential Desktop
            // credential; PKCE/state/loopback checks remain the security boundary.
            "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID": .string(BrevConstants.googleMacOSOAuthClientID),
            "BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI": .string(BrevConstants.googleMacOSOAuthRedirectURI),
            "BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME": .string(BrevConstants.googleMacOSOAuthCallbackScheme),
            "BREV_MICROSOFT_OAUTH_CLIENT_ID": .string(BrevConstants.microsoftOAuthClientID)
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
    ),
    targets: [
        .target(
            name: "BrevMacOS",
            destinations: .macOS,
            product: .app,
            productName: "Brev",
            bundleId: BrevConstants.bundleIDPrefix,
            deploymentTargets: BrevConstants.macOSDeploymentTarget,
            infoPlist: .file(path: "Resources/Info.plist"),
            sources: ["Sources/**"],
            resources: [
                "Resources/Assets.xcassets",
                "Resources/AppIcon.icon",
                "Resources/Localizable.xcstrings",
                "Resources/InfoPlist.xcstrings"
            ],
            entitlements: .file(path: "Resources/BrevMacOS.entitlements"),
            dependencies: [
                .package(product: "BrevBackend", type: .runtime),
                .package(product: "BrevGmail", type: .runtime),
                .package(product: "BrevDesign", type: .runtime),
                .package(product: "BrevExamplePlugin", type: .runtime),
                .package(product: "BrevMail", type: .runtime),
                .package(product: "BrevPlugins", type: .runtime),
                .package(product: "BrevSettings", type: .runtime),
                .package(product: "BrevSyncEngine", type: .runtime),
                .package(product: "BrevThemes", type: .runtime),
                .external(name: "Sparkle")
            ],
            settings: .settings(
                base: [
                    "BREV_APP_PRODUCT_NAME": "Brev",
                    "BREV_APP_BUNDLE_ID": .string(BrevConstants.bundleIDPrefix),
                    "PRODUCT_NAME": "$(BREV_APP_PRODUCT_NAME)",
                    "PRODUCT_BUNDLE_IDENTIFIER": "$(BREV_APP_BUNDLE_ID)",
                    "PRODUCT_MODULE_NAME": "BrevMacOS"
                ],
                configurations: [
                    .debug(name: "Debug", settings: [
                        "CODE_SIGN_ENTITLEMENTS": "Resources/BrevMacOS.entitlements"
                    ]),
                    .release(name: "Release", settings: [
                        "CODE_SIGN_ENTITLEMENTS": "Resources/BrevMacOSRelease.entitlements"
                    ])
                ]
            )
        )
    ],
    schemes: [
        .scheme(
            name: "BrevMacOS",
            shared: true,
            buildAction: .buildAction(targets: ["BrevMacOS"]),
            runAction: .runAction(configuration: "Debug", executable: "BrevMacOS")
        )
    ]
)
