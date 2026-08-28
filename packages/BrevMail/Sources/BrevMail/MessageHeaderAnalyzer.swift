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
        authenticationResults: String?
    ) -> SenderAuthWarning? {
        let nameSpoof = hasDisplayNameMismatch(from: header.from)
        let dmarcFail = hasDMARCFail(in: authenticationResults)

        switch (nameSpoof, dmarcFail) {
        case (true, true): return .dmarcFailAndDisplayNameMismatch
        case (false, true): return .dmarcFail
        case (true, false): return .displayNameMismatch
        case (false, false): return nil
        }
    }

    // MARK: Display name check

    /// Returns `true` when the `From:` display name contains a domain-like substring
    /// that differs from the actual sender email domain. This catches the common pattern
    /// of "Security Notice <attacker@phish.example>" where the display name impersonates
    /// a trusted domain.
    static func hasDisplayNameMismatch(from correspondent: Correspondent) -> Bool {
        guard let rawName = correspondent.name else { return false }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = correspondent.email.lowercased()

        guard let atIndex = email.lastIndex(of: "@") else { return false }
        let senderDomain = String(email[email.index(after: atIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !senderDomain.isEmpty else { return false }

        // Look for a domain-like token in the display name (contains a dot, no spaces).
        let domainPattern = #"(?<!\w)([\w-]+\.[\w.-]{2,})(?!\w)"#
        guard let regex = try? NSRegularExpression(pattern: domainPattern) else { return false }
        let range = NSRange(name.startIndex..., in: name)
        let matches = regex.matches(in: name.lowercased(), range: range)
        for match in matches {
            guard let r = Range(match.range, in: name) else { continue }
            let candidate = String(name[r]).lowercased()
            // If the candidate domain appears in the display name but the actual sender
            // is on a completely different domain, flag it.
            if candidate != senderDomain, !senderDomain.hasSuffix(".\(candidate)"),
               !candidate.hasSuffix(".\(senderDomain)") {
                return true
            }
        }
        return false
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
}
