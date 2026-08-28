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

/// Backend mode selected for a Google account.
public enum GoogleOAuthProviderMode: String, Sendable, Hashable, Codable {
    /// Native Gmail API backend.
    case gmailAPI = "gmail-api"
    /// Standards-based IMAP/SMTP fallback.
    case imapSMTP = "imap-smtp"
}

/// The native Google client platform used to select a client and callback.
public enum GoogleOAuthPlatform: String, Sendable, Hashable, Codable {
    case macOS
    case iOS
}

/// Persisted, non-secret Google account metadata shared by Gmail API and the
/// IMAP/SMTP fallback.
public struct GoogleOAuthAccountConfiguration: Sendable, Hashable, Codable {
    /// Stable Google OIDC subject returned by token-bound UserInfo.
    public let subject: String
    /// The currently verified Google account email address.
    public let email: String
    /// Optional verified Workspace hosted domain.
    public let hostedDomain: String?
    /// Scopes actually granted by Google.
    public let grantedScopes: Set<String>
    /// Native client platform used for authorization.
    public let platform: GoogleOAuthPlatform
    /// Backend mode to restore for this account.
    public let providerMode: GoogleOAuthProviderMode
    /// Access-token expiry metadata retained for diagnostics and restore.
    public let accessTokenExpiresAt: Date?
    /// Refresh-token expiry metadata supplied by Google's Testing project.
    public let refreshTokenExpiresAt: Date?

    /// Stable account key for a Google API account.
    public var accountID: String {
        switch providerMode {
        case .gmailAPI:
            return BrevAccount.gmailAPIAccountID(forGoogleSubject: subject)
        case .imapSMTP:
            return BrevAccount.imapSMTPAccountID(forEmailAddress: email)
        }
    }

    /// Creates persisted Google account metadata.
    public init(
        subject: String,
        email: String,
        hostedDomain: String? = nil,
        grantedScopes: Set<String> = [],
        platform: GoogleOAuthPlatform,
        providerMode: GoogleOAuthProviderMode = .gmailAPI,
        accessTokenExpiresAt: Date? = nil,
        refreshTokenExpiresAt: Date? = nil
    ) {
        self.subject = Self.normalise(subject)
        self.email = Self.normalise(email)
        self.hostedDomain = Self.normaliseOptional(hostedDomain)
        self.grantedScopes = Set(
            grantedScopes
                .map(Self.normalise)
                .filter { !$0.isEmpty }
        )
        self.platform = platform
        self.providerMode = providerMode
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case subject
        case email
        case hostedDomain
        case grantedScopes
        case platform
        case providerMode
        case accessTokenExpiresAt
        case refreshTokenExpiresAt
    }

    /// Decodes old metadata records that predate provider mode, platform, or
    /// expiry fields. Missing provider mode intentionally restores to the
    /// IMAP/SMTP fallback so existing accounts are never silently migrated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subject = try Self.normalise(container.decodeIfPresent(String.self, forKey: .subject) ?? "")
        email = try Self.normalise(container.decodeIfPresent(String.self, forKey: .email) ?? "")
        hostedDomain = try Self.normaliseOptional(
            container.decodeIfPresent(String.self, forKey: .hostedDomain)
        )
        let scopes = try container.decodeIfPresent(Set<String>.self, forKey: .grantedScopes) ?? []
        grantedScopes = Set(scopes.map(Self.normalise).filter { !$0.isEmpty })
        platform = try container.decodeIfPresent(GoogleOAuthPlatform.self, forKey: .platform) ?? .macOS
        providerMode = try container.decodeIfPresent(GoogleOAuthProviderMode.self, forKey: .providerMode) ?? .imapSMTP
        accessTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpiresAt)
        refreshTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .refreshTokenExpiresAt)
    }

    private static func normalise(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normaliseOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalised = normalise(value)
        return normalised.isEmpty ? nil : normalised
    }
}

/// A fully-resolved Google native OAuth configuration for one Apple platform.
public struct GoogleOAuthPlatformConfiguration: Sendable, Hashable {
    /// The public OAuth client ID.
    public let clientID: String
    /// The configured redirect URI, or the loopback base on macOS.
    public let redirectURI: String
    /// The callback scheme intercepted by the native session or local listener.
    public let callbackScheme: String
    /// The platform represented by this configuration.
    public let platform: GoogleOAuthPlatform

    /// Creates a platform-specific Google OAuth configuration.
    public init(
        clientID: String,
        redirectURI: String,
        callbackScheme: String,
        platform: GoogleOAuthPlatform
    ) {
        self.clientID = Self.normalise(clientID)
        self.redirectURI = Self.normalise(redirectURI)
        self.callbackScheme = Self.normalise(callbackScheme)
        self.platform = platform
    }

    /// Returns a reverse-DNS callback scheme for a Google client ID.
    ///
    /// Google exposes this value as the iOS URL scheme. For example,
    /// `123.apps.googleusercontent.com` becomes
    /// `com.googleusercontent.apps.123`.
    public static func reversedClientID(_ clientID: String) -> String? {
        let value = normalise(clientID)
        guard !value.isEmpty else { return nil }
        let fields = value.split(separator: ".", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }
        return fields.reversed().joined(separator: ".")
    }

    /// Describes a configuration error without exposing credentials.
    public var validationError: String? {
        guard !clientID.isEmpty else { return "client ID is empty" }
        guard let redirect = URLComponents(string: redirectURI),
              let scheme = redirect.scheme,
              !scheme.isEmpty,
              redirect.host == nil || !redirect.host!.isEmpty
        else { return "redirect URI is malformed" }

        guard !callbackScheme.isEmpty else { return "callback scheme is empty" }
        guard callbackScheme == scheme else {
            return "callback scheme does not match redirect URI scheme"
        }

        if platform == .macOS {
            guard scheme == "http", redirect.host == "127.0.0.1" else {
                return "macOS Desktop clients require an HTTP loopback callback on 127.0.0.1"
            }
            return nil
        }

        guard scheme != "http", scheme != "https",
              scheme.contains("."),
              scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil
        else { return "custom callback scheme must be reverse-DNS and contain a period" }

        if let reversed = Self.reversedClientID(clientID), callbackScheme != reversed {
            return "iOS callback scheme must match the reversed client ID"
        }
        return nil
    }

    /// Whether this configuration passes native-client callback validation.
    public var isValid: Bool { validationError == nil }

    private static func normalise(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
