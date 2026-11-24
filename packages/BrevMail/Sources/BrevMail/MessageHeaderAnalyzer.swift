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

import BrevBackend
import Foundation

// MARK: - SenderAuthWarning

/// The severity level of a sender authentication warning.
public enum SenderAuthWarning: Equatable, Sendable {
    /// The display name domain doesn't match the envelope sender domain (yellow).
    case displayNameMismatch
    /// The message failed DMARC validation (red — likely spoofed).
    case dmarcFail
    /// Both DMARC failed and the display name is mismatched.
    case dmarcFailAndDisplayNameMismatch
    /// The address resembles this familiar domain or claims its brand name.
    case lookAlikeDomain(String)
}

// MARK: - MessageHeaderAnalyzer

/// Analyzes message headers to detect sender-spoofing and authentication failures.
///
/// All analysis is local — no network calls are made. The analyzer relies on:
/// - `MessageHeader.from`: for display-name-vs-domain comparison
/// - `MessageBody.authenticationResults`: for DMARC/SPF/DKIM result parsing
///
/// Per ADR-0028 invariant 1, this type is view-layer only and takes
/// provider-neutral `MessageHeader`/`MessageBody` inputs.
public enum MessageHeaderAnalyzer {
    /// Returns a warning if the message exhibits spoofing signals, or `nil` if clean.
    public static func warning(
        for header: MessageHeader,
        authenticationResults: String?,
        writtenAddresses: Set<String> = [],
        knownDomains: Set<String> = []
    ) -> SenderAuthWarning? {
        let email = header.from.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dmarcFail = hasDMARCFail(in: authenticationResults)
        // An unauthenticated From address is not proof that this is the
        // correspondent we wrote to. Keep explicit failures visible.
        guard !writtenAddresses.contains(email) else { return dmarcFail ? .dmarcFail : nil }
        let nameSpoof = hasDisplayNameMismatch(from: header.from)

        switch (nameSpoof, dmarcFail) {
        case (true, true): return .dmarcFailAndDisplayNameMismatch
        case (false, true): return .dmarcFail
        case (true, false): return .displayNameMismatch
        case (false, false):
            guard let at = email.lastIndex(of: "@"),
                  let domain = SenderDomainComparison.claimedDomain(
                      name: header.from.name, domain: String(email[email.index(after: at)...]), knownDomains: knownDomains
                  ) else { return nil }
            return .lookAlikeDomain(domain)
        }
    }

    // MARK: Display name check

    /// Returns `true` when the `From:` display name contains a domain-like substring
    /// that differs from the actual sender email domain. This catches the common pattern
    /// of "Security Notice <attacker@phish.example>" where the display name impersonates
    /// a trusted domain.
    static func hasDisplayNameMismatch(from correspondent: Correspondent) -> Bool {
        MessageSecurityWarningPolicy.displayNameDomainWarning(for: correspondent) != nil
    }

    // MARK: Authentication-Results parsing

    /// Returns `true` when the `Authentication-Results` header reports a DMARC
    /// `fail` or `permerror`. `permerror` (a malformed/unevaluable DMARC record)
    /// is treated as a failure too — a real gap the prior `fail`-only check
    /// missed. `temperror` is excluded because it is a transient DNS condition,
    /// not a spoof signal. (DMARC already incorporates SPF/DKIM *alignment*, so
    /// raw SPF/DKIM results are intentionally not surfaced here, where a broken
    /// forward would otherwise produce noisy false warnings.)
    static func hasDMARCFail(in authenticationResults: String?) -> Bool {
        guard let value = authenticationResults else { return false }
        // Authentication-Results may be multi-line (header folding); normalize whitespace.
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .lowercased()
        return normalized.range(
            of: #"\bdmarc\s*=\s*(fail|permerror)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// Returns `true` when `Authentication-Results` reports a sender authentication
    /// failure that must block automatic trusted-sender remote-image loading:
    /// - any `dmarc=fail` or `dmarc=permerror` (always blocks), or
    /// - `spf=fail`/`softfail`/`permerror` or `dkim=fail`/`permerror` when `dmarc=pass`
    ///   is not present (allowing legitimately forwarded mail with passing aligned DMARC
    ///   while blocking spoofed/unauthenticated headers).
    static func hasSenderAuthenticationFailure(in authenticationResults: String?) -> Bool {
        guard let value = authenticationResults else { return false }
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .lowercased()
        if normalized.range(
            of: #"\bdmarc\s*=\s*(fail|permerror)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let hasDMARCPass = normalized.range(
            of: #"\bdmarc\s*=\s*pass\b"#,
            options: .regularExpression
        ) != nil
        guard !hasDMARCPass else { return false }
        return normalized.range(
            of: #"\b(spf\s*=\s*(fail|softfail|permerror)|dkim\s*=\s*(fail|permerror))\b"#,
            options: .regularExpression
        ) != nil
    }
}
