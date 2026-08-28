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

// MARK: - Server protocol kind

/// Which mail protocol an endpoint speaks.
public enum MailServerProtocolKind: String, Sendable, Hashable, Codable, CaseIterable {
    case imap
    case smtp
    /// ManageSieve (RFC 5804) server-side rule endpoint.
    case manageSieve
}

// MARK: - TLS mode

/// Transport security mode for a mail server connection.
public enum MailServerTLSMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Implicit TLS from the first byte (IMAP port 993, SMTP port 465). Preferred.
    case implicit
    /// STARTTLS upgrade on a plain connection (IMAP port 143, SMTP port 587).
    case startTLS
}

// MARK: - Authentication mechanism

/// Authentication mechanism advertised or required by a mail server.
public enum MailServerAuthentication: String, Sendable, Hashable, Codable, CaseIterable {
    /// Standard plaintext password over TLS.
    case password
    /// Provider-generated app-specific password (e.g. iCloud, ProtonMail Bridge).
    case appPassword
    /// CRAM-MD5 or similar challenge/response encrypted-password mechanism (not supported by Brev).
    case encryptedPassword
    /// XOAUTH2 / OAuth2 bearer token authentication.
    case xoauth2
    /// No authentication (rare; local proxies only).
    case none
}

// MARK: - Server settings

/// Connection parameters for a single IMAP or SMTP endpoint.
///
/// Used in `IMAPAccountConfiguration` for both incoming and outgoing
/// servers. `usernameTemplate` is expanded at login time by substituting
/// `%EMAILADDRESS%` with the account's email address.
public struct MailServerSettings: Sendable, Hashable, Codable {
    public let kind: MailServerProtocolKind
    public var host: String
    public var port: UInt16
    public let tlsMode: MailServerTLSMode
    public var authentication: MailServerAuthentication
    public var usernameTemplate: String

    public init(
        kind: MailServerProtocolKind,
        host: String,
        port: UInt16,
        tlsMode: MailServerTLSMode,
        authentication: MailServerAuthentication = .password,
        usernameTemplate: String = "%EMAILADDRESS%"
    ) {
        self.kind = kind
        self.host = host
        self.port = port
        self.tlsMode = tlsMode
        self.authentication = authentication
        self.usernameTemplate = usernameTemplate
    }

    /// Resolves the username for `emailAddress` by substituting `%EMAILADDRESS%` and `%LOCALPART%`.
    ///
    /// `%LOCALPART%` expands to the text before `@`; used by providers like iCloud
    /// whose IMAP username is the email local part only.
    public func resolvedUsername(for emailAddress: String) -> String {
        let localPart = emailAddress.split(separator: "@", maxSplits: 1).first.map(String.init) ?? emailAddress
        return usernameTemplate
            .replacingOccurrences(of: "%EMAILADDRESS%", with: emailAddress)
            .replacingOccurrences(of: "%LOCALPART%", with: localPart)
    }
}

// MARK: - Discovery error

/// Errors that `MailAccountAutodiscovery` and its callers can throw.
public enum MailAccountAutodiscoveryError: Error, Equatable, LocalizedError, Sendable {
    /// The provided email address is not a valid address.
    case invalidEmailAddress
    /// Discovery timed out or failed with an underlying network error.
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEmailAddress:
            String(localized: "The email address is not valid.", bundle: .module)
        case .networkFailure(let message):
            String(localized: "Settings discovery failed: \(message)", bundle: .module)
        }
    }
}

// MARK: - Discovery result

/// How the settings in a `MailAccountDiscoveryResult` were obtained.
public enum MailAccountDiscoverySource: String, Sendable, Hashable, Codable {
    /// Matched a built-in provider profile bundled with Brev.
    case builtInProfile
    /// Fetched from the provider's Thunderbird-style autoconfig endpoint.
    case providerAutoconfig
    /// Resolved from DNS SRV records for the email domain.
    case dnsSRV
    /// Resolved by matching the domain's DNS MX exchanger to a known provider
    /// (e.g. an MX of `in1-smtp.messagingengine.com` → the Fastmail profile).
    case dnsMXProvider
    /// User-facing defaults derived from the email domain (e.g. `imap.<domain>:993`).
    case manualFallback
}

/// A fully resolved set of IMAP + SMTP server settings for an email account.
///
/// Produced by `MailAccountAutodiscovery` and consumed by `IMAPAccountSetupSheet`
/// and `IMAPAccountProvisioner`. The `source` field lets the UI communicate
/// confidence level to the user.
public struct MailAccountDiscoveryResult: Sendable, Hashable {
    /// The email domain these settings cover (lower-cased, e.g. `"fastmail.com"`).
    public let domain: String
    /// Human-readable provider name from the discovery source, if available.
    public let displayName: String?
    /// How these settings were obtained.
    public let source: MailAccountDiscoverySource
    /// The autoconfig URL that provided these settings, if applicable.
    public let sourceURL: URL?
    /// IMAP incoming server settings.
    public var incoming: MailServerSettings?
    /// SMTP outgoing server settings.
    public var outgoing: MailServerSettings?
    /// Optional user-confirmed ManageSieve endpoint for server-side rule sync.
    public var manageSieve: MailServerSettings?
    /// Whether the user should review the settings before adding the account.
    public let requiresManualReview: Bool

    public init(
        domain: String,
        displayName: String?,
        source: MailAccountDiscoverySource,
        sourceURL: URL? = nil,
        incoming: MailServerSettings?,
        outgoing: MailServerSettings?,
        manageSieve: MailServerSettings? = nil,
        requiresManualReview: Bool = false
    ) {
        self.domain = domain
        self.displayName = displayName
        self.source = source
        self.sourceURL = sourceURL
        self.incoming = incoming
        self.outgoing = outgoing
        self.manageSieve = manageSieve
        self.requiresManualReview = requiresManualReview
    }
}
