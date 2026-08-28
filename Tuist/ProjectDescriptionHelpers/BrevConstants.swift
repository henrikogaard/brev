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

import Foundation
import ProjectDescription

/// Shared build constants used across `apps/*/Project.swift` manifests.
///
/// Centralizing these here ensures bundle ID / deployment-target / team
/// drift can't happen accidentally during agent edits.
public enum BrevConstants {
    /// Reverse-DNS namespace owned by Brev.
    public static let bundleIDPrefix = "eu.brevmail.brev"

    /// Apple Developer Team ID used for local signing and release archives.
    public static let teamID = "45AD7E7G5G"

    /// Minimum deployment targets. See ADR-0004.
    public static let macOSDeploymentTarget: DeploymentTargets = .macOS("14.0")
    public static let iOSDeploymentTarget: DeploymentTargets = .iOS("17.0")

    /// Default Swift version for fresh Brev code.
    public static let swiftVersion: SettingValue = "6.0"

    /// Marketing version surfaced in Info.plist. Bumped per release
    /// (ADR-0009).
    public static let marketingVersion = "0.1.0"

    /// Build number. Local build tooling bumps this per build; the
    /// in-repo value is a safe fallback for direct Xcode invocations.
    public static let buildNumber = "1"

    // MARK: - OAuth client credentials (ADR-0028 standards-first OAuth)

    /// Google macOS/Desktop OAuth2 client ID.
    public static var googleMacOSOAuthClientID: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID")
            ?? (localQAFallbackEnabled ? oauthEnvironmentValue("BREV_GOOGLE_OAUTH_CLIENT_ID") : nil)
            ?? ""
    }

    /// Google iOS OAuth2 client ID.
    public static var googleIOSOAuthClientID: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_IOS_CLIENT_ID")
            ?? (localQAFallbackEnabled ? oauthEnvironmentValue("BREV_GOOGLE_OAUTH_CLIENT_ID") : nil)
            ?? ""
    }

    /// Google macOS loopback base. The app adds an ephemeral port and callback
    /// path after its local listener is ready.
    public static var googleMacOSOAuthRedirectURI: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI")
            ?? "http://127.0.0.1"
    }

    /// Google macOS loopback callback scheme.
    public static var googleMacOSOAuthCallbackScheme: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME")
            ?? "http"
    }

    /// Exact Google iOS redirect URI. If omitted, the app derives it from the
    /// reversed iOS client ID at runtime.
    public static var googleIOSOAuthRedirectURI: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI")
            ?? "\(googleIOSOAuthCallbackScheme):/oauth2redirect"
    }

    /// Google iOS callback scheme. If omitted, the app derives Google's
    /// reversed-client-ID scheme at runtime.
    public static var googleIOSOAuthCallbackScheme: String {
        oauthEnvironmentValue("BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME")
            ?? reversedClientID(googleIOSOAuthClientID)
            ?? "eu.brevmail.brev"
    }

    /// Microsoft (Azure) OAuth2 client ID. See `googleOAuthClientID`.
    public static var microsoftOAuthClientID: String {
        oauthEnvironmentValue("BREV_MICROSOFT_OAUTH_CLIENT_ID") ?? ""
    }

    private static var localQAFallbackEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["BREV_LOCAL_QA"]
            ?? ProcessInfo.processInfo.environment["BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK"]
            ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private static func reversedClientID(_ clientID: String) -> String? {
        let fields = clientID.split(separator: ".", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }
        return fields.reversed().joined(separator: ".")
    }

    private static func oauthEnvironmentValue(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
