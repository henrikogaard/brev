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

/// Pure assessor for the ADR-0088 scoped Gmail trust rule.
///
/// Reads only the topmost `Authentication-Results` header that Gmail's
/// receiving MX prepends at SMTP receipt. Any other header claiming
/// `mx.google.com` fails closed, so a sender-supplied forged copy blocks
/// the assessment instead of being silently ignored. The assessor never
/// logs or stores header values; only the aligned From domain leaves it.
public enum GmailSignInTrustAssessor {
    /// Assesses one message's headers in Gmail API order.
    /// - Parameter headers: `payload.headers` as returned by `messages.get`,
    ///   in received order.
    public static func assess(headers: [GmailMessageHeader]) -> SignInTrustAssessment {
        let results = headers
            .filter { $0.name.caseInsensitiveCompare("Authentication-Results") == .orderedSame }
            .map { unfold($0.value) }
        guard let topmost = results.first else {
            return .unavailable(.noTrustedHeader)
        }
        guard let authservID = authservIdentifier(topmost) else {
            return .unavailable(.malformedHeader)
        }
        guard authservID == "mx.google.com" else {
            return .unavailable(.noTrustedHeader)
        }
        for lower in results.dropFirst()
            where authservIdentifier(lower) == "mx.google.com" {
            return .unavailable(.conflictingTrustedHeaders)
        }

        let methodTokens = topmost.split(whereSeparator: { $0 == ";" || $0.isWhitespace })
            .filter { $0.prefix(6).caseInsensitiveCompare("dmarc=") == .orderedSame }
        guard methodTokens.count <= 1 else { return .unavailable(.duplicateDMARC) }
        let dmarcResults = dmarcSegments(topmost)
        guard !dmarcResults.isEmpty else { return .unavailable(.missingDMARC) }
        guard dmarcResults.count == 1 else { return .unavailable(.duplicateDMARC) }
        let dmarc = dmarcResults[0]
        guard let result = dmarc.result, !result.isEmpty else {
            return .unavailable(.malformedHeader)
        }
        guard result.caseInsensitiveCompare("pass") == .orderedSame else {
            return .unavailable(.dmarcNotPass)
        }
        guard let headerFromDomain = dmarc.headerFrom?.lowercased(), !headerFromDomain.isEmpty else {
            return .unavailable(.malformedHeader)
        }

        let fromHeaders = headers.filter {
            $0.name.caseInsensitiveCompare("From") == .orderedSame
        }
        guard fromHeaders.count == 1 else { return .unavailable(.malformedFrom) }
        let mailboxes = GmailAPIBackend.correspondents(fromHeaders[0].value)
        guard mailboxes.count == 1,
              let domain = mailboxDomain(mailboxes[0].email) else {
            return .unavailable(.malformedFrom)
        }
        guard domain == headerFromDomain else { return .unavailable(.fromMismatch) }
        return .pass(fromDomain: domain)
    }

    /// Collapses RFC 5322 CRLF folding — every run of CR, LF, space or tab
    /// becomes a single space, then the value is trimmed. A folded
    /// `Authentication-Results` value must read exactly like its unfolded
    /// form before the `;`-segment grammar applies.
    private static func unfold(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var inWhitespaceRun = false
        // Scalar iteration is deliberate: CRLF is one Character, so a
        // per-Character `\r` match would never fire.
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWhitespaceRun = true
            } else {
                if inWhitespaceRun && !result.isEmpty { result.append(" ") }
                result.unicodeScalars.append(scalar)
                inWhitespaceRun = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The trimmed, lowercased authserv-id of one `Authentication-Results`
    /// header — the token before the first `;`. A header without a
    /// `;`-delimited result section or with an empty identifier is
    /// unparseable.
    private static func authservIdentifier(_ value: String) -> String? {
        guard let semicolon = value.firstIndex(of: ";") else { return nil }
        let token = value[..<semicolon].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token.lowercased()
    }

    /// One parsed `dmarc=` method-result segment: its result token and the
    /// `header.from` property inside the same `;`-segment.
    private struct DmarcResult {
        let result: String?
        let headerFrom: String?
    }

    /// Splits a header into `;`-segments and returns every segment whose
    /// first token is `dmarc=<result>`.
    private static func dmarcSegments(_ value: String) -> [DmarcResult] {
        value.split(separator: ";").compactMap { raw in
            let segment = raw.trimmingCharacters(in: .whitespaces)
            guard segment.count >= 6,
                  segment.prefix(6).caseInsensitiveCompare("dmarc=") == .orderedSame else {
                return nil
            }
            var result: String?
            var headerFrom: String?
            var headerFromCount = 0
            for token in segment.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                if result == nil, token.count > 6,
                   token.prefix(6).caseInsensitiveCompare("dmarc=") == .orderedSame {
                    result = String(token.dropFirst(6))
                } else if token.count >= 12,
                          token.prefix(12).caseInsensitiveCompare("header.from=") == .orderedSame {
                    headerFromCount += 1
                    headerFrom = String(token.dropFirst(12)).trimmingCharacters(
                        in: CharacterSet(charactersIn: "<>; "))
                }
            }
            return DmarcResult(result: result, headerFrom: headerFromCount == 1 ? headerFrom : nil)
        }
    }

    /// Lowercased domain part of a single mailbox address.
    private static func mailboxDomain(_ email: String) -> String? {
        guard let at = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: at)...].trimmingCharacters(in: .whitespaces)
        return domain.isEmpty ? nil : domain.lowercased()
    }
}

/// In-memory registry of message IDs observed as fresh deliveries by the
/// Gmail history delta (ADR-0088). Entries expire after 10 minutes and the
/// registry is capped at 200; nothing is persisted.
final class GmailFreshDeliveryRegistry: @unchecked Sendable {
    private let now: @Sendable () -> Date
    private let lifetime: TimeInterval
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [(id: String, observedAt: Date)] = []

    /// Creates a registry.
    /// - Parameters:
    ///   - now: clock injected for tests.
    ///   - lifetime: entry lifetime in seconds (10 minutes).
    ///   - capacity: maximum entries before the oldest are evicted.
    init(
        now: @escaping @Sendable () -> Date = { Date() },
        lifetime: TimeInterval = 600,
        capacity: Int = 200
    ) {
        self.now = now
        self.lifetime = lifetime
        self.capacity = capacity
    }

    /// Records freshly delivered message IDs with the current observation time.
    func record(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            let observedAt = now()
            pruneExpired(at: observedAt)
            // Sorted so a batch over the cap evicts deterministically.
            for id in ids.sorted() where !entries.contains(where: { $0.id == id }) {
                entries.append((id: id, observedAt: observedAt))
            }
            while entries.count > capacity {
                entries.removeFirst()
            }
        }
    }

    /// Returns whether the ID is a live (unexpired) fresh delivery.
    func contains(_ id: String) -> Bool {
        lock.withLock {
            pruneExpired(at: now())
            return entries.contains { $0.id == id }
        }
    }

    /// Invalidates delivery provenance when a provider connection ends or restarts.
    func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    private func pruneExpired(at instant: Date) {
        entries.removeAll { instant.timeIntervalSince($0.observedAt) >= lifetime }
    }
}
