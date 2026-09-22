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

// BrevIOS — the iOS app target.
//
// Per ADR-0028 and ADR-0029, standards-first IMAP/SMTP account setup
// is the default shipping path. Native Gmail API accounts are added through
// the dedicated BrevGmail adapter; other providers remain IMAP/SMTP.

let project = Project(
    name: "BrevIOS",
    organizationName: "Brev",
    packages: [
        .package(path: "../../packages/BrevBackend"),
        .package(path: "../../packages/BrevCalendar"),
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
            "TARGETED_DEVICE_FAMILY": "1,2",
            // Public platform-specific OAuth values are injected into Info.plist.
            // Native PKCE clients do not ship a Google client secret.
            "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID": .string(BrevConstants.googleIOSOAuthClientID),
            "BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI": .string(BrevConstants.googleIOSOAuthRedirectURI),
            "BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME": .string(BrevConstants.googleIOSOAuthCallbackScheme),
            "BREV_MICROSOFT_OAUTH_CLIENT_ID": .string(BrevConstants.microsoftOAuthClientID),
            // Google Picker credentials for Drive attachments (#14).
            "BREV_GOOGLE_API_KEY": .string(BrevConstants.googleAPIKey),
            "BREV_GOOGLE_APP_ID": .string(BrevConstants.googleAppID),
            "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "YES",
            "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES": "BrevIconEnvelopeDarkMetal BrevIconEnvelopeCarbon"
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
    ),
    targets: [
        .target(
            name: "BrevIOS",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "\(BrevConstants.bundleIDPrefix).ios",
            deploymentTargets: BrevConstants.iOSDeploymentTarget,
            infoPlist: .file(path: "Resources/Info.plist"),
            sources: ["Sources/**"],
            resources: [
                "Resources/Assets.xcassets",
                "Resources/PrivacyInfo.xcprivacy",
                "Resources/Localizable.xcstrings",
                "Resources/InfoPlist.xcstrings"
            ],
            entitlements: .file(path: "Resources/BrevIOS.entitlements"),
            dependencies: [
                .package(product: "BrevBackend", type: .runtime),
                .package(product: "BrevCalendar", type: .runtime),
                .package(product: "BrevGmail", type: .runtime),
                .package(product: "BrevDesign", type: .runtime),
                .package(product: "BrevExamplePlugin", type: .runtime),
                .package(product: "BrevMail", type: .runtime),
                .package(product: "BrevPlugins", type: .runtime),
                .package(product: "BrevSettings", type: .runtime),
                .package(product: "BrevSyncEngine", type: .runtime),
                .package(product: "BrevThemes", type: .runtime),
                .target(name: "BrevShareExtension"),
                .target(name: "BrevNotificationContent")
            ]
        ),
        .target(
            name: "BrevShareExtension",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "\(BrevConstants.bundleIDPrefix).ios.share-extension",
            deploymentTargets: BrevConstants.iOSDeploymentTarget,
            infoPlist: .file(path: "BrevShareExtension/Info.plist"),
            sources: ["BrevShareExtension/**"],
            resources: ["BrevShareExtension/Resources/Localizable.xcstrings"],
            entitlements: .file(path: "BrevShareExtension/BrevShareExtension.entitlements"),
            dependencies: [],
            settings: .settings(
                base: [
                    // ADR-0004: compile extensions in the application-extension
                    // context so extension-prohibited APIs are hard errors.
                    "APPLICATION_EXTENSION_API_ONLY": "YES"
                ]
            )
        ),
        // BrevIOSTests — the iOS app unit test bundle (ADR-0004).
        //
        // Depends on BrevIOS for `@testable` access to the app shell
        // (background-refresh coordinator, URL handling). The share
        // extension cannot be linked by a test bundle, so its pure
        // handoff-URL source file is compiled into this target directly.
        .target(
            name: "BrevIOSTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "\(BrevConstants.bundleIDPrefix).ios.tests",
            deploymentTargets: BrevConstants.iOSDeploymentTarget,
            sources: [
                "../iOSTests/**",
                "BrevShareExtension/ShareHandoffURL.swift"
            ],
            dependencies: [
                .target(name: "BrevIOS"),
                .package(product: "BrevMail", type: .runtime)
            ]
        ),
        .target(
            name: "BrevNotificationContent",
            destinations: [.iPhone, .iPad],
            product: .appExtension,
            bundleId: "\(BrevConstants.bundleIDPrefix).ios.notification-content",
            deploymentTargets: BrevConstants.iOSDeploymentTarget,
            infoPlist: .file(path: "BrevNotificationContent/Info.plist"),
            sources: ["BrevNotificationContent/**"],
            dependencies: [],
            settings: .settings(
                base: [
                    // ADR-0004: compile extensions in the application-extension
                    // context so extension-prohibited APIs are hard errors.
                    "APPLICATION_EXTENSION_API_ONLY": "YES"
                ]
            )
        )
    ],
    schemes: [
        .scheme(
            name: "BrevIOS",
            shared: true,
            buildAction: .buildAction(targets: ["BrevIOS"]),
            testAction: .targets(["BrevIOSTests"]),
            runAction: .runAction(configuration: "Debug", executable: "BrevIOS")
        )
    ]
)
