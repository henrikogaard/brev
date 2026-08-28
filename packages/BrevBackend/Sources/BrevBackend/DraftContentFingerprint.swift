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

import CryptoKit
import Foundation

/// Versioned content fingerprint for draft reconciliation (#306).
public struct DraftContentFingerprint: Equatable, Sendable, Hashable, Codable {
    public static let currentVersion = "v1"

    public let version: String
    public let digest: String

    public init(version: String, digest: String) {
        self.version = version
        self.digest = digest
    }

    /// Fingerprints stable draft fields while excluding volatile IDs and timestamps.
    public static func fingerprint(
        for draft: Draft,
        messageID: String? = nil
    ) -> DraftContentFingerprint {
        let payload = normalizedPayload(for: draft, messageID: messageID)
        let digest = SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return DraftContentFingerprint(version: currentVersion, digest: digest)
    }

    static func normalizedPayload(for draft: Draft, messageID: String?) -> String {
        var lines = ["version=\(currentVersion)"]
        if let messageID, !messageID.isEmpty {
            lines.append("message-id=\(normalizeScalar(messageID))")
        }
        if let threadID = draft.threadID, !threadID.isEmpty {
            lines.append("thread-id=\(normalizeScalar(threadID))")
        }
        if let inReplyTo = draft.inReplyToMessageID, !inReplyTo.isEmpty {
            lines.append("in-reply-to=\(normalizeScalar(inReplyTo))")
        }
        if let forwarded = draft.forwardedMessageID, !forwarded.isEmpty {
            lines.append("forwarded=\(normalizeScalar(forwarded))")
        }
        lines.append("subject=\(normalizeScalar(draft.subject))")
        lines.append(contentsOf: recipientLines(prefix: "to", recipients: draft.to))
        lines.append(contentsOf: recipientLines(prefix: "cc", recipients: draft.cc))
        lines.append(contentsOf: recipientLines(prefix: "bcc", recipients: draft.bcc))
        lines.append("body=\(normalizeBody(draft.htmlBody))")
        return lines.joined(separator: "\n")
    }

    private static func recipientLines(prefix: String, recipients: [Correspondent]) -> [String] {
        recipients
            .sorted { $0.email.lowercased() < $1.email.lowercased() }
            .map { recipient in
                let name = normalizeScalar(recipient.name ?? "")
                let email = normalizeScalar(recipient.email)
                return "\(prefix)=\(name)<\(email)>"
            }
    }

    static func normalizeScalar(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizeBody(_ htmlBody: String) -> String {
        let decodedEntities = htmlBody
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let withoutTags = decodedEntities
            .replacingOccurrences(of: "(?is)<style.*?>.*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<script.*?>.*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return normalizeScalar(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

public struct DraftSyncMetadata: Equatable, Sendable, Codable {
    public var lastSyncedFingerprint: DraftContentFingerprint?
    public var isDirty: Bool
    public var conflictDraftID: Draft.ID?

    public init(
        lastSyncedFingerprint: DraftContentFingerprint? = nil,
        isDirty: Bool = false,
        conflictDraftID: Draft.ID? = nil
    ) {
        self.lastSyncedFingerprint = lastSyncedFingerprint
        self.isDirty = isDirty
        self.conflictDraftID = conflictDraftID
    }
}

public enum DraftReconciliationDecision: Equatable, Sendable {
    case acceptRemote
    case keepLocal
    case createConflict(local: Draft, remote: Draft)
}

public enum DraftReconciliation {
    /// Reconciles a remote draft update against the staged local copy.
    public static func reconcile(
        local: Draft,
        remote: Draft,
        metadata: DraftSyncMetadata,
        messageID: String? = nil
    ) -> DraftReconciliationDecision {
        let localFingerprint = DraftContentFingerprint.fingerprint(for: local, messageID: messageID)
        let remoteFingerprint = DraftContentFingerprint.fingerprint(for: remote, messageID: messageID)

        if localFingerprint == remoteFingerprint {
            return .acceptRemote
        }

        if metadata.isDirty {
            if metadata.lastSyncedFingerprint == remoteFingerprint {
                return .keepLocal
            }
            return .createConflict(local: local, remote: remote)
        }

        return .acceptRemote
    }

    /// Bounded send/save recovery when the provider outcome is ambiguous.
    public static func matchesSendCandidate(
        draft: Draft,
        messageID: String?,
        expectedFingerprint: DraftContentFingerprint
    ) -> Bool {
        DraftContentFingerprint.fingerprint(for: draft, messageID: messageID) == expectedFingerprint
    }
}
