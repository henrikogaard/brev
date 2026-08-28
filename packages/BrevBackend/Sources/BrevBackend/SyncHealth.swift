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

/// A summary of what a background refresh pass accomplished.
public struct BackgroundRefreshSnapshot: Sendable, Hashable, Codable {
    /// Number of folders whose first message page was refreshed.
    public let refreshedFolderCount: Int
    /// Number of folders skipped due to the per-refresh limit.
    public let deferredFolderCount: Int
    /// When the refresh completed.
    public let refreshedAt: Date

    public init(refreshedFolderCount: Int, deferredFolderCount: Int, refreshedAt: Date) {
        self.refreshedFolderCount = refreshedFolderCount
        self.deferredFolderCount = deferredFolderCount
        self.refreshedAt = refreshedAt
    }
}

/// Privacy-safe progress for a full local search-index rebuild.
///
/// Counts are aggregate only so diagnostics and Settings can show useful
/// progress without exposing folder names, subjects, addresses, or queries.
public struct SearchIndexProgressSnapshot: Sendable, Hashable, Codable {
    public let completedFolderCount: Int
    public let totalFolderCount: Int
    public let indexedMessageCount: Int
    public let bodyBackfillFailureCount: Int

    public init(
        completedFolderCount: Int,
        totalFolderCount: Int,
        indexedMessageCount: Int,
        bodyBackfillFailureCount: Int = 0
    ) {
        self.completedFolderCount = completedFolderCount
        self.totalFolderCount = totalFolderCount
        self.indexedMessageCount = indexedMessageCount
        self.bodyBackfillFailureCount = bodyBackfillFailureCount
    }
}

public struct AccountSyncHealth: Sendable, Hashable, Codable {
    public let sourceID: MailSourceID
    public let state: SyncHealthState
    public let lastSuccessfulSyncAt: Date?
    public let lastErrorDescription: String?
    public let indexStatus: SearchIndexStatus
    public let cacheSizeBytes: Int
    public let localSearchIndexMetrics: LocalSearchIndexMetrics?
    public let pendingMutationCount: Int
    /// Number of replay conflicts that have not yet been dismissed by the user.
    public let replayConflictCount: Int
    /// Result of the most recent background refresh, if one has been performed.
    public let backgroundRefreshSnapshot: BackgroundRefreshSnapshot?
    /// Aggregate progress for the active full local search-index rebuild.
    public let searchIndexProgress: SearchIndexProgressSnapshot?

    public init(
        sourceID: MailSourceID,
        state: SyncHealthState,
        lastSuccessfulSyncAt: Date?,
        lastErrorDescription: String?,
        indexStatus: SearchIndexStatus,
        cacheSizeBytes: Int,
        localSearchIndexMetrics: LocalSearchIndexMetrics? = nil,
        pendingMutationCount: Int,
        replayConflictCount: Int = 0,
        backgroundRefreshSnapshot: BackgroundRefreshSnapshot? = nil,
        searchIndexProgress: SearchIndexProgressSnapshot? = nil
    ) {
        self.sourceID = sourceID
        self.state = state
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastErrorDescription = lastErrorDescription
        self.indexStatus = indexStatus
        self.cacheSizeBytes = cacheSizeBytes
        self.localSearchIndexMetrics = localSearchIndexMetrics
        self.pendingMutationCount = pendingMutationCount
        self.replayConflictCount = replayConflictCount
        self.backgroundRefreshSnapshot = backgroundRefreshSnapshot
        self.searchIndexProgress = searchIndexProgress
    }

    public var requiresUserAction: Bool {
        state == .authenticationRequired
    }

    public var canRetryWithoutUserAction: Bool {
        switch state {
        case .healthy, .syncing, .authenticationRequired, .indexing:
            false
        case .offline, .providerError, .degraded:
            true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sourceID
        case state
        case lastSuccessfulSyncAt
        case lastErrorDescription
        case indexStatus
        case cacheSizeBytes
        case localSearchIndexMetrics
        case pendingMutationCount
        case replayConflictCount
        case backgroundRefreshSnapshot
        case searchIndexProgress
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceID: container.decode(MailSourceID.self, forKey: .sourceID),
            state: container.decode(SyncHealthState.self, forKey: .state),
            lastSuccessfulSyncAt: container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt),
            lastErrorDescription: container.decodeIfPresent(String.self, forKey: .lastErrorDescription),
            indexStatus: container.decode(SearchIndexStatus.self, forKey: .indexStatus),
            cacheSizeBytes: container.decode(Int.self, forKey: .cacheSizeBytes),
            localSearchIndexMetrics: container.decodeIfPresent(
                LocalSearchIndexMetrics.self,
                forKey: .localSearchIndexMetrics
            ),
            pendingMutationCount: container.decode(Int.self, forKey: .pendingMutationCount),
            replayConflictCount: container.decodeIfPresent(
                Int.self,
                forKey: .replayConflictCount
            ) ?? 0,
            backgroundRefreshSnapshot: container.decodeIfPresent(
                BackgroundRefreshSnapshot.self,
                forKey: .backgroundRefreshSnapshot
            ),
            searchIndexProgress: container.decodeIfPresent(
                SearchIndexProgressSnapshot.self,
                forKey: .searchIndexProgress
            )
        )
    }
}

// MARK: - Replay conflict record

/// A mutation conflict surfaced to the user for review. One record per
/// unresolved conflict. The user can dismiss individual records or clear
/// all at once.
///
/// This is a view-facing value type; backends produce these from their
/// internal `MutationConflict` records via `SyncConflictManaging`.
public struct ReplayConflict: Sendable, Hashable, Codable, Identifiable {
    /// Stable identifier — matches the originating `MutationConflict.id`.
    public let id: UUID
    /// The folder the mutation targeted (e.g. "Inbox", "Archive").
    public let folderName: String
    /// Human-readable description of what was attempted (e.g. "Mark read").
    public let operationDescription: String
    /// Why the mutation failed (e.g. "The item no longer exists on the server").
    public let failureReason: String
    /// When the conflict was detected.
    public let detectedAt: Date

    public init(
        id: UUID,
        folderName: String,
        operationDescription: String,
        failureReason: String,
        detectedAt: Date
    ) {
        self.id = id
        self.folderName = folderName
        self.operationDescription = operationDescription
        self.failureReason = failureReason
        self.detectedAt = detectedAt
    }
}

public enum SyncHealthState: String, Sendable, Hashable, Codable, CaseIterable {
    case healthy
    case syncing
    case offline
    case authenticationRequired
    case providerError
    case indexing
    case degraded
}

public enum SearchIndexStatus: Sendable, Hashable, Codable {
    case notBuilt
    case rebuilding(progress: Double?)
    case ready(messageCount: Int)
    case failed(String)
}

public struct SyncDiagnosticReport: Sendable, Hashable, Codable {
    public let accountDisplayName: String
    public let backendDisplayName: String
    public let health: AccountSyncHealth

    public init(
        accountDisplayName: String,
        backendDisplayName: String,
        health: AccountSyncHealth
    ) {
        self.accountDisplayName = accountDisplayName
        self.backendDisplayName = backendDisplayName
        self.health = health
    }

    public func redactedText() -> String {
        let parts = [
            "Account: \(accountDisplayName)",
            "Backend: \(backendDisplayName)",
            "State: \(health.state.rawValue)",
            "Last successful sync: \(health.lastSuccessfulSyncAt?.description ?? "never")",
            "Index: \(health.indexStatus.diagnosticDescription)",
            "Index database bytes: \(health.localSearchIndexMetrics?.databaseBytes ?? 0)",
            "Indexed headers: \(health.localSearchIndexMetrics?.indexedHeaderCount ?? 0)",
            "Cached bodies: \(health.localSearchIndexMetrics?.cachedBodyCount ?? 0)",
            "Search documents: \(health.localSearchIndexMetrics?.searchDocumentCount ?? 0)",
            "Indexed folders: \(health.localSearchIndexMetrics?.syncedFolderCount ?? 0)",
            "Index progress: \(health.searchIndexProgress?.diagnosticDescription ?? "none")",
            "Cache bytes: \(health.cacheSizeBytes)",
            "Pending mutations: \(health.pendingMutationCount)",
            "Replay conflicts: \(health.replayConflictCount)",
            "Last error: \(health.lastErrorDescription ?? "none")"
        ]
        return Self.redact(parts.joined(separator: "\n"))
    }

    private static func redact(_ text: String) -> String {
        let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        // Keyword + separator (`:`/`=`, incl. the no-space `key=value` form) or
        // whitespace + value; trailing `\b` avoids matching inside longer words.
        let tokenPattern =
            #"(?i)\b(Bearer|token|access_token|refresh_token|api_key|apikey|secret|client_secret|password|app[-_]?password|passphrase|pwd)\b\s*(?:[:=]\s*|\s+)[A-Za-z0-9._~+/\-=]+"#
        return text
            .replacingMatches(pattern: emailPattern, with: "[redacted-email]")
            .replacingMatches(pattern: tokenPattern) { match in
                let prefix = match
                    .split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "=" })
                    .first
                    .map(String.init) ?? "Token"
                return "\(prefix) [redacted-token]"
            }
    }
}

private extension SearchIndexProgressSnapshot {
    var diagnosticDescription: String {
        let failureSuffix: String
        if bodyBackfillFailureCount > 0 {
            let noun = bodyBackfillFailureCount == 1 ? "body cache failure" : "body cache failures"
            failureSuffix = ", \(bodyBackfillFailureCount) \(noun)"
        } else {
            failureSuffix = ""
        }
        return "\(completedFolderCount)/\(totalFolderCount) folders, "
            + "\(indexedMessageCount) indexed messages"
            + failureSuffix
    }
}

private extension SearchIndexStatus {
    var diagnosticDescription: String {
        switch self {
        case .notBuilt:
            "not-built"
        case .rebuilding(let progress):
            if let progress {
                "rebuilding \(progress)"
            } else {
                "rebuilding"
            }
        case .ready(let messageCount):
            "ready \(messageCount) messages"
        case .failed(let message):
            "failed \(message)"
        }
    }
}

private extension String {
    func replacingMatches(pattern: String, with replacement: String) -> String {
        replacingMatches(pattern: pattern) { _ in replacement }
    }

    func replacingMatches(pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return self
        }
        let nsRange = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: nsRange).reversed()
        var result = self
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}
