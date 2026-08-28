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

// MARK: - Password-based autodiscovery

/// Authentication mode used by a built-in provider profile.
public enum PasswordAuthMode: String, Sendable, Hashable, Codable {
    /// Standard IMAP/SMTP password authentication.
    case password
    /// App-specific password (e.g. ProtonMail Bridge local proxy, iCloud app passwords).
    case appPassword
    /// OAuth2 bearer token (XOAUTH2). Profile is provided for endpoint discovery only;
    /// password-based login is not supported.
    case xoauth2
}

/// A fully resolved set of IMAP + SMTP settings for a provider.
///
/// Returned by `MailAccountAutodiscovery.matchBuiltInProfile(for:)` when
/// the email domain matches a known provider. All fields are ready to hand
/// directly to an IMAP/SMTP client.
public struct DiscoveredSettings: Sendable, Hashable {
    /// A human-readable provider label (e.g. "Zoho Mail").
    public let providerName: String
    /// Resolved IMAP connection parameters.
    public let imap: IMAPConfiguration
    /// Resolved SMTP connection parameters.
    public let smtp: SMTPConfiguration
    /// Authentication mechanism the provider expects.
    public let authMode: PasswordAuthMode
    /// Username template for the incoming (IMAP) server. Defaults to `%EMAILADDRESS%`.
    public let incomingUsernameTemplate: String
    /// Username template for the outgoing (SMTP) server. Defaults to `%EMAILADDRESS%`.
    public let outgoingUsernameTemplate: String

    public init(
        providerName: String,
        imap: IMAPConfiguration,
        smtp: SMTPConfiguration,
        authMode: PasswordAuthMode,
        incomingUsernameTemplate: String = "%EMAILADDRESS%",
        outgoingUsernameTemplate: String = "%EMAILADDRESS%"
    ) {
        self.providerName = providerName
        self.imap = imap
        self.smtp = smtp
        self.authMode = authMode
        self.incomingUsernameTemplate = incomingUsernameTemplate
        self.outgoingUsernameTemplate = outgoingUsernameTemplate
    }
}

// MARK: - Built-in profile resolver

/// Resolves a mail domain to a built-in IMAP/SMTP provider profile.
///
/// Returns `nil` for unknown domains; the caller is responsible for
/// showing a manual-entry form in that case.
public enum MailAccountAutodiscovery {
    // MARK: - New discovery API (returns MailAccountDiscoveryResult)

    /// Looks up built-in settings for the email domain, if a profile exists.
    ///
    /// Returns `nil` for unknown domains. The caller should fall through to
    /// DNS SRV, provider autoconfig, then `manualFallback(forEmailAddress:)`.
    public static func profile(forEmailAddress emailAddress: String) -> MailAccountDiscoveryResult? {
        let domain = emailDomain(from: emailAddress)
        guard let discovered = matchBuiltInProfile(for: domain) else {
            return nil
        }
        let auth: MailServerAuthentication
        switch discovered.authMode {
        case .appPassword: auth = .appPassword
        case .xoauth2: auth = .xoauth2
        case .password: auth = .password
        }
        return MailAccountDiscoveryResult(
            domain: domain,
            displayName: discovered.providerName,
            source: .builtInProfile,
            sourceURL: nil,
            incoming: MailServerSettings(
                kind: .imap,
                host: discovered.imap.host,
                port: discovered.imap.port,
                tlsMode: discovered.imap.tlsMode == .implicit ? .implicit : .startTLS,
                authentication: auth,
                usernameTemplate: discovered.incomingUsernameTemplate
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: discovered.smtp.host,
                port: discovered.smtp.port,
                tlsMode: discovered.smtp.tlsMode == .implicit ? .implicit : .startTLS,
                authentication: auth,
                usernameTemplate: discovered.outgoingUsernameTemplate
            ),
            requiresManualReview: false
        )
    }

    /// Returns Gmail IMAP/SMTP settings keyed to any Google Workspace address.
    ///
    /// Google OAuth returns the user's full Workspace address, which does not
    /// have a `gmail.com` domain even though its IMAP/SMTP endpoints are the
    /// Gmail endpoints. Explicit Google onboarding uses this helper instead of
    /// falling through to generic autodiscovery.
    public static func googleProfile(forEmailAddress emailAddress: String) -> MailAccountDiscoveryResult? {
        guard let base = profile(forEmailAddress: "user@gmail.com") else { return nil }
        return MailAccountDiscoveryResult(
            domain: emailDomain(from: emailAddress),
            displayName: base.displayName,
            source: base.source,
            sourceURL: base.sourceURL,
            incoming: base.incoming,
            outgoing: base.outgoing,
            manageSieve: base.manageSieve,
            requiresManualReview: base.requiresManualReview
        )
    }

    /// Resolves settings by matching the domain's DNS MX exchangers to a
    /// built-in provider profile.
    ///
    /// Most custom domains delegate mail to a known provider via MX without
    /// publishing IMAP/SMTP SRV records or a usable autoconfig endpoint. When
    /// the most-preferred exchanger belongs to a provider Brev knows, this
    /// returns that provider's servers re-keyed to the user's own domain (the
    /// provider username templates still resolve against the real email
    /// address). Returns `nil` when no exchanger matches a known provider.
    public static func providerResult(
        forMXRecords records: [MailMXRecord],
        emailAddress: String
    ) -> MailAccountDiscoveryResult? {
        guard let providerDomain = MailMXProviderResolver.providerDomain(for: records),
              let base = profile(forEmailAddress: "user@\(providerDomain)")
        else {
            return nil
        }
        return MailAccountDiscoveryResult(
            domain: emailDomain(from: emailAddress),
            displayName: base.displayName,
            source: .dnsMXProvider,
            sourceURL: nil,
            incoming: base.incoming,
            outgoing: base.outgoing,
            requiresManualReview: base.requiresManualReview
        )
    }

    /// Returns conservative manual-entry defaults derived from the email domain.
    ///
    /// Used when all discovery methods fail. The caller should always show
    /// the server settings fields when this result is used.
    public static func manualFallback(forEmailAddress emailAddress: String) -> MailAccountDiscoveryResult {
        let domain = emailDomain(from: emailAddress)
        return MailAccountDiscoveryResult(
            domain: domain,
            displayName: nil,
            source: .manualFallback,
            sourceURL: nil,
            incoming: MailServerSettings(
                kind: .imap,
                host: "imap.\(domain)",
                port: 993,
                tlsMode: .implicit,
                authentication: .password
            ),
            outgoing: MailServerSettings(
                kind: .smtp,
                host: "smtp.\(domain)",
                port: 587,
                tlsMode: .startTLS,
                authentication: .password
            ),
            requiresManualReview: true
        )
    }

    // MARK: - Validation helpers

    /// Returns `true` if `emailAddress` has a non-empty local part (no whitespace) and a plausibly
    /// valid domain (contains a dot, no leading/trailing dots, no consecutive dots, no underscores).
    public static func isValidEmailAddress(_ emailAddress: String) -> Bool {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty
        else {
            return false
        }
        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.contains(where: { $0.isWhitespace }) else { return false }
        return isValidServerHost(domain)
    }

    /// Returns `true` if `host` is a valid FQDN hostname (a strict per-label
    /// allowlist: ASCII alphanumerics and interior hyphens, no leading/trailing
    /// dot, at least two labels).
    ///
    /// This is deliberately strict because the value is interpolated into an
    /// autodiscovery URL's authority and an IMAP/SMTP server field. The previous
    /// blocklist accepted URL-significant characters like `@`/`/`/`:`/`?`, so an
    /// email such as `you@company.com@evil.com` produced a "host" whose userinfo
    /// moved the autoconfig probe (and the user's email) to an attacker host that
    /// could then return attacker IMAP/SMTP settings.
    public static func isValidServerHost(_ host: String) -> Bool {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // A single trailing dot denotes a fully-qualified, root-anchored name
        // (`imap.example.org.`) and is legitimate — it's canonicalized away
        // before storage. Drop it before per-label validation. A leading dot,
        // or a doubled trailing dot, remains invalid.
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard !trimmed.isEmpty, !trimmed.hasPrefix("."), !trimmed.hasSuffix(".") else { return false }
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  let first = label.first, let last = label.last,
                  first.isASCII, first.isLetter || first.isNumber,
                  last.isASCII, last.isLetter || last.isNumber,
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else {
                return false
            }
        }
        return true
    }

    // MARK: - Legacy built-in profile API (DiscoveredSettings)

    /// Matches a well-known provider profile for the given email domain.
    ///
    /// Domain comparison is case-insensitive. Returns `nil` when no
    /// built-in profile matches.
    ///
    /// - Parameter emailDomain: The domain portion of the user's email address.
    public static func matchBuiltInProfile(for emailDomain: String) -> DiscoveredSettings? {
        let domain = emailDomain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch domain {
        // ProtonMail Bridge — local proxy; app-password auth.
        // Bridge listens on loopback; the user generates the password inside Bridge.
        case "proton.me", "protonmail.com", "protonmail.ch", "pm.me":
            return DiscoveredSettings(
                providerName: "ProtonMail Bridge",
                imap: IMAPConfiguration(host: "127.0.0.1", port: 1143, tlsMode: .startTLS),
                smtp: SMTPConfiguration(host: "127.0.0.1", port: 1025, tlsMode: .startTLS),
                authMode: .appPassword
            )
        // Zoho Mail
        case "zoho.com", "zohomail.com", "zoho.eu", "zoho.in":
            return DiscoveredSettings(
                providerName: "Zoho Mail",
                imap: IMAPConfiguration(host: "imap.zoho.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.zoho.com", port: 465, tlsMode: .implicit),
                authMode: .password
            )
        // GMX
        case "gmx.com", "gmx.net", "gmx.de", "gmx.at", "gmx.ch":
            return DiscoveredSettings(
                providerName: "GMX",
                imap: IMAPConfiguration(host: "imap.gmx.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.gmx.com", port: 465, tlsMode: .implicit),
                authMode: .password
            )
        // Web.de
        case "web.de":
            return DiscoveredSettings(
                providerName: "Web.de",
                imap: IMAPConfiguration(host: "imap.web.de", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.web.de", port: 465, tlsMode: .implicit),
                authMode: .password
            )
        // Mailbox.org
        case "mailbox.org":
            return DiscoveredSettings(
                providerName: "Mailbox.org",
                imap: IMAPConfiguration(host: "imap.mailbox.org", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.mailbox.org", port: 465, tlsMode: .implicit),
                authMode: .password
            )
        // Posteo — uses the apex domain for both IMAP and SMTP
        case "posteo.de", "posteo.net", "posteo.at", "posteo.ch", "posteo.be", "posteo.eu":
            return DiscoveredSettings(
                providerName: "Posteo",
                imap: IMAPConfiguration(host: "posteo.de", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "posteo.de", port: 587, tlsMode: .startTLS),
                authMode: .password
            )
        // Runbox
        case "runbox.com":
            return DiscoveredSettings(
                providerName: "Runbox",
                imap: IMAPConfiguration(host: "imap.runbox.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.runbox.com", port: 465, tlsMode: .implicit),
                authMode: .password
            )
        // iCloud Mail — IMAP username is local part only; SMTP uses full email address
        case "icloud.com", "me.com", "mac.com":
            return DiscoveredSettings(
                providerName: "iCloud Mail",
                imap: IMAPConfiguration(host: "imap.mail.me.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.mail.me.com", port: 587, tlsMode: .startTLS),
                authMode: .appPassword,
                incomingUsernameTemplate: "%LOCALPART%",
                outgoingUsernameTemplate: "%EMAILADDRESS%"
            )
        // Microsoft 365 / Outlook — requires OAuth2; password auth is not supported
        case "outlook.com", "hotmail.com", "live.com", "msn.com":
            return DiscoveredSettings(
                providerName: "Outlook",
                imap: IMAPConfiguration(host: "outlook.office365.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.office365.com", port: 587, tlsMode: .startTLS),
                authMode: .xoauth2
            )
        // Fastmail — IMAP/SMTP require an app-specific password (the account
        // password is rejected for mail protocols).
        case "fastmail.com", "fastmail.fm", "fastmail.us", "messagingengine.com":
            return DiscoveredSettings(
                providerName: "Fastmail",
                imap: IMAPConfiguration(host: "imap.fastmail.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.fastmail.com", port: 465, tlsMode: .implicit),
                authMode: .appPassword
            )
        // Yahoo Mail — requires an app password for IMAP/SMTP.
        case "yahoo.com", "yahoo.co.uk", "ymail.com", "rocketmail.com":
            return DiscoveredSettings(
                providerName: "Yahoo Mail",
                imap: IMAPConfiguration(host: "imap.mail.yahoo.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.mail.yahoo.com", port: 465, tlsMode: .implicit),
                authMode: .appPassword
            )
        // AOL Mail — requires an app password for IMAP/SMTP.
        case "aol.com":
            return DiscoveredSettings(
                providerName: "AOL Mail",
                imap: IMAPConfiguration(host: "imap.aol.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.aol.com", port: 465, tlsMode: .implicit),
                authMode: .appPassword
            )
        // Gmail — OAuth2 is preferred; password IMAP needs an app password.
        case "gmail.com", "googlemail.com":
            return DiscoveredSettings(
                providerName: "Gmail",
                imap: IMAPConfiguration(host: "imap.gmail.com", port: 993, tlsMode: .implicit),
                smtp: SMTPConfiguration(host: "smtp.gmail.com", port: 465, tlsMode: .implicit),
                authMode: .xoauth2
            )
        default:
            return nil
        }
    }

    // MARK: - Private helpers

    private static func emailDomain(from emailAddress: String) -> String {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]).lowercased() : ""
    }
}
