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

/// Local evidence explaining why a sender qualifies for automatic remote-image
/// loading under the opt-in trusted-sender tier.
public enum TrustedSenderSource: Equatable, Hashable, Sendable {
    /// Exact normalized email match found in local Contacts.
    case localContacts
    /// Exact normalized email match found in local outgoing / replied-to history.
    case repliedToSender
}

/// Evaluates whether a sender address qualifies as trusted using strictly local
/// email sets (local Contacts and locally recorded outgoing/replied-to recipients).
///
/// Matching is exact on normalized email addresses and never performs domain-only
/// matching (domain allowlisting remains explicit in `RemoteContentPolicy`).
public struct TrustedSenderEvaluator: Equatable, Sendable {
    /// Normalized email addresses known from local Contacts.
    public let contactEmails: Set<String>
    /// Normalized email addresses the user has previously emailed or replied to.
    public let repliedToEmails: Set<String>

    /// An evaluator with no trusted senders (fail-closed default).
    public static let empty = TrustedSenderEvaluator()

    /// Creates an evaluator from local contact and replied-to email sequences.
    /// - Parameters:
    ///   - contactEmails: Raw email addresses from local Contacts; empty/malformed entries are ignored.
    ///   - repliedToEmails: Raw email addresses from local sent/replied-to history; empty/malformed entries are ignored.
    public init(
        contactEmails: some Sequence<String> = EmptyCollection<String>(),
        repliedToEmails: some Sequence<String> = EmptyCollection<String>()
    ) {
        self.contactEmails = Set(contactEmails.compactMap(Self.normalizedEmail))
        self.repliedToEmails = Set(repliedToEmails.compactMap(Self.normalizedEmail))
    }

    /// Returns the trust source for `senderEmail`, or `nil` when sender authentication
    /// failed, the address is malformed, or it is not present in either local trust set.
    /// - Parameters:
    ///   - senderEmail: The message sender's email address.
    ///   - senderAuthenticationFailed: `true` when SPF/DKIM/DMARC authentication failed for the message.
    public func trustSource(
        for senderEmail: String,
        senderAuthenticationFailed: Bool = false
    ) -> TrustedSenderSource? {
        guard !senderAuthenticationFailed else { return nil }
        guard let normalized = Self.normalizedEmail(senderEmail) else { return nil }
        if contactEmails.contains(normalized) {
            return .localContacts
        }
        if repliedToEmails.contains(normalized) {
            return .repliedToSender
        }
        return nil
    }

    /// Returns `true` when `senderEmail` matches a normalized local Contact or
    /// previously emailed recipient and sender authentication has not failed.
    /// - Parameters:
    ///   - senderEmail: The message sender's email address.
    ///   - senderAuthenticationFailed: `true` when SPF/DKIM/DMARC authentication failed for the message.
    public func isTrusted(
        senderEmail: String,
        senderAuthenticationFailed: Bool = false
    ) -> Bool {
        trustSource(for: senderEmail, senderAuthenticationFailed: senderAuthenticationFailed) != nil
    }

    /// Normalizes and validates an email address for exact trusted-sender matching.
    /// Rejects empty strings, whitespace inside the address, multiple `@` characters,
    /// and domains without at least two non-empty dot-separated labels.
    /// - Parameter value: Raw email address string.
    public static func normalizedEmail(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let localPart = parts[0]
        let domainPart = parts[1]
        guard !localPart.isEmpty,
              !domainPart.isEmpty,
              !localPart.contains(where: \.isWhitespace),
              !domainPart.contains(where: \.isWhitespace) else {
            return nil
        }
        let labels = domainPart.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return normalized
    }
}

public extension RemoteContentPolicy {
    /// Evaluates whether remote content is allowed by either the explicit
    /// sender/domain allowlist or (when opted in) the local trusted-sender tier.
    /// - Parameters:
    ///   - senderEmail: The message sender's email address.
    ///   - resourceHost: Optional remote asset host to check against domain allowlists.
    ///   - allowTrustedSenders: Whether the opt-in trusted-sender tier is enabled.
    ///   - trustedSenders: Local Contacts and replied-to evaluator.
    ///   - senderAuthenticationFailed: `true` when SPF/DKIM/DMARC authentication failed for the message.
    func allows(
        senderEmail: String,
        resourceHost: String?,
        allowTrustedSenders: Bool,
        trustedSenders: TrustedSenderEvaluator,
        senderAuthenticationFailed: Bool = false
    ) -> Bool {
        if allows(senderEmail: senderEmail, resourceHost: resourceHost) {
            return true
        }
        guard allowTrustedSenders else { return false }
        return trustedSenders.isTrusted(
            senderEmail: senderEmail,
            senderAuthenticationFailed: senderAuthenticationFailed
        )
    }
}
