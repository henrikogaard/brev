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

/// Errors emitted while reconciling Gmail's full or history-based state.
public enum GmailSyncError: Error, Sendable, Equatable, LocalizedError {
    /// The persisted history cursor is no longer available and a full sync is
    /// required. The cursor is intentionally retained in the local store.
    case fullSyncRequired(historyID: String)
    /// Delta sync was requested before a full-sync cursor existed.
    case missingHistoryCursor
    /// The API failed while a sync was being assembled.
    case api(GmailAPIError)
    /// The local store rejected an atomic commit.
    case store(GmailAccountStoreError)
    /// Gmail returned the same pagination cursor twice.
    case repeatedHistoryPageToken(String)
    /// History pagination exceeded the configured safety bound.
    case historyPaginationLimitExceeded(limit: Int)
    /// A history response contained more events than the configured bound.
    case historyEventLimitExceeded(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .fullSyncRequired:
            return String(localized: "Gmail needs a full sync before incremental changes can be applied.", bundle: .module)
        case .missingHistoryCursor:
            return String(localized: "Gmail has not completed its initial sync yet.", bundle: .module)
        case .api(let error): return error.localizedDescription
        case .store(let error): return error.localizedDescription
        case .repeatedHistoryPageToken:
            return String(localized: "Gmail returned a repeated history page cursor.", bundle: .module)
        case .historyPaginationLimitExceeded(let limit):
            return String(localized: "Gmail history exceeded the page limit (\(limit)).", bundle: .module)
        case .historyEventLimitExceeded(let limit):
            return String(localized: "Gmail history exceeded the event limit (\(limit)).", bundle: .module)
        }
    }
}

/// Bounds the concurrent detail fetches used by a Gmail reconciliation.
public struct GmailSyncConfiguration: Sendable, Equatable {
    /// Maximum number of in-flight `messages.get` calls. The conservative
    /// default leaves quota headroom for profile, label, and list requests.
    public let maxConcurrentDetailFetches: Int
    /// Number of references requested from each list page.
    public let pageSize: Int
    /// Maximum number of recent message headers cached by the initial sync.
    /// Older mail remains available through Gmail search and paged reads.
    public let maxInitialMessages: Int
    /// Maximum history pages fetched in one delta reconciliation.
    public let maxHistoryPages: Int
    /// Maximum history events assembled before one atomic commit.
    public let maxHistoryEvents: Int

    /// Creates sync bounds, clamping concurrency to Gmail's safe batch range.
    public init(
        maxConcurrentDetailFetches: Int = 10,
        pageSize: Int = 100,
        maxInitialMessages: Int = 250,
        maxHistoryPages: Int = 100,
        maxHistoryEvents: Int = 10000
    ) {
        self.maxConcurrentDetailFetches = min(50, max(1, maxConcurrentDetailFetches))
        self.pageSize = min(500, max(1, pageSize))
        self.maxInitialMessages = max(1, maxInitialMessages)
        self.maxHistoryPages = max(1, maxHistoryPages)
        self.maxHistoryEvents = max(1, maxHistoryEvents)
    }
}

/// Builds and atomically commits Gmail account snapshots and history deltas.
public final class GmailSyncReconciler: @unchecked Sendable {
    private let client: any GmailAPIClientProtocol
    private let store: any GmailAccountStore
    private let accountID: String
    private let configuration: GmailSyncConfiguration

    /// Creates a reconciler for one stable Gmail account identifier.
    public init(
        client: any GmailAPIClientProtocol,
        store: any GmailAccountStore,
        accountID: String,
        configuration: GmailSyncConfiguration = .init()
    ) {
        self.client = client
        self.store = store
        self.accountID = accountID
        self.configuration = configuration
    }

    /// Performs an initial full synchronization and atomically replaces the
    /// account snapshot only after all pages and detail requests succeed.
    @discardableResult
    public func fullSync() async throws -> GmailAccountState {
        try Task.checkCancellation()
        let profile = try await api { try await client.getProfile() }
        let labels = try await api { try await client.listLabels() }
        let references = try await collectMessageReferences()
        let messages = try await fetchDetails(for: references.map(\.id))
        try Task.checkCancellation()

        let state = GmailAccountState(
            accountID: accountID,
            emailAddress: profile.emailAddress,
            historyID: profile.historyID,
            lastFullSyncAt: Date()
        )
        do {
            try await store.replaceSnapshot(
                GmailAccountSnapshot(accountID: accountID, state: state, labels: labels, messages: messages)
            )
            return state
        } catch let error as GmailAccountStoreError {
            throw GmailSyncError.store(error)
        } catch {
            throw GmailSyncError.store(.databaseFailure)
        }
    }

    /// Applies all available history pages as one atomic, idempotent delta.
    /// An expired cursor is surfaced as `fullSyncRequired` without changing the
    /// persisted cursor or cached messages.
    @discardableResult
    public func deltaSync() async throws -> GmailAccountState {
        try Task.checkCancellation()
        guard let current = try await store.accountState(accountID: accountID),
              let historyID = current.historyID,
              !historyID.isEmpty
        else {
            throw GmailSyncError.missingHistoryCursor
        }

        let pages: [GmailHistoryPage]
        do {
            pages = try await collectHistoryPages(startHistoryID: historyID)
        } catch let error as GmailAPIError where error == .httpFailure(statusCode: 404) {
            throw GmailSyncError.fullSyncRequired(historyID: historyID)
        } catch let error as GmailSyncError {
            if case .api(.httpFailure(statusCode: 404)) = error {
                throw GmailSyncError.fullSyncRequired(historyID: historyID)
            }
            throw error
        } catch let error as GmailAPIError {
            throw GmailSyncError.api(error)
        }

        var finalActions: [String: Bool] = [:]
        for page in pages {
            for event in page.history {
                for change in event.messagesAdded {
                    finalActions[change.message.id] = true
                }
                for change in event.labelsAdded {
                    finalActions[change.message.id] = true
                }
                for change in event.labelsRemoved {
                    finalActions[change.message.id] = true
                }
                // A deletion in the same history record wins over any other
                // event representation for that message.
                for change in event.messagesDeleted {
                    finalActions[change.message.id] = false
                }
            }
        }

        let changedIDs = finalActions.compactMap { $0.value ? $0.key : nil }.sorted()
        let deletedIDs = finalActions.compactMap { $0.value ? nil : $0.key }.sorted()
        let messages = try await fetchDetails(for: changedIDs)
        let currentLabels = try await store.labels(accountID: accountID)
        let labels = try await api { try await client.listLabels() }
        let currentLabelIDs = Set(currentLabels.map(\.id))
        let nextLabelIDs = Set(labels.map(\.id))
        let finalHistoryID = pages.reversed().compactMap(\.historyID).first ?? historyID
        let delta = GmailStoreDelta(
            accountID: accountID,
            upsertedLabels: labels,
            removedLabelIDs: labels.isEmpty ? [] : currentLabelIDs.subtracting(nextLabelIDs).sorted(),
            upsertedMessages: messages,
            removedMessageIDs: deletedIDs,
            historyID: finalHistoryID,
            lastDeltaSyncAt: Date()
        )
        do {
            try await store.apply(delta)
            guard let updated = try await store.accountState(accountID: accountID) else {
                throw GmailSyncError.store(.accountMismatch)
            }
            return updated
        } catch let error as GmailSyncError {
            throw error
        } catch let error as GmailAccountStoreError {
            throw GmailSyncError.store(error)
        } catch {
            throw GmailSyncError.store(.databaseFailure)
        }
    }

    /// Chooses a full or delta sync based on the persisted cursor.
    @discardableResult
    public func sync() async throws -> GmailAccountState {
        if let historyID = try await store.accountState(accountID: accountID)?.historyID,
           !historyID.isEmpty {
            return try await deltaSync()
        }
        return try await fullSync()
    }

    private func collectMessageReferences() async throws -> [GmailMessageReference] {
        var pageToken: String?
        var references: [GmailMessageReference] = []
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let remaining = configuration.maxInitialMessages - references.count
            guard remaining > 0 else { break }
            let page = try await api {
                try await client.listMessages(
                    maxResults: min(configuration.pageSize, remaining),
                    pageToken: pageToken,
                    labelIDs: [],
                    query: nil,
                    includeSpamTrash: true
                )
            }
            for reference in page.messages where seen.insert(reference.id).inserted {
                references.append(reference)
                if references.count == configuration.maxInitialMessages { break }
            }
            pageToken = references.count < configuration.maxInitialMessages ? page.nextPageToken : nil
        } while pageToken != nil
        return references
    }

    private func collectHistoryPages(startHistoryID: String) async throws -> [GmailHistoryPage] {
        var pageToken: String?
        var pages: [GmailHistoryPage] = []
        var visitedPageTokens = Set<String>()
        var eventCount = 0
        repeat {
            try Task.checkCancellation()
            if pages.count >= configuration.maxHistoryPages {
                throw GmailSyncError.historyPaginationLimitExceeded(limit: configuration.maxHistoryPages)
            }
            if let pageToken, !visitedPageTokens.insert(pageToken).inserted {
                throw GmailSyncError.repeatedHistoryPageToken(pageToken)
            }
            let page = try await api {
                try await client.listHistory(
                    startHistoryID: startHistoryID,
                    maxResults: configuration.pageSize,
                    pageToken: pageToken,
                    labelID: nil,
                    historyTypes: []
                )
            }
            eventCount += page.history.count
            if eventCount > configuration.maxHistoryEvents {
                throw GmailSyncError.historyEventLimitExceeded(limit: configuration.maxHistoryEvents)
            }
            pages.append(page)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return pages
    }

    private func fetchDetails(for ids: [String]) async throws -> [GmailMessage] {
        guard !ids.isEmpty else { return [] }
        var details: [GmailMessage] = []
        for start in stride(from: 0, to: ids.count, by: configuration.maxConcurrentDetailFetches) {
            try Task.checkCancellation()
            let end = min(start + configuration.maxConcurrentDetailFetches, ids.count)
            let chunk = Array(ids[start ..< end])
            let fetched = try await withThrowingTaskGroup(of: GmailMessage.self, returning: [GmailMessage].self) { group in
                for id in chunk {
                    group.addTask {
                        try Task.checkCancellation()
                        return try await self.api {
                            try await self.client.getMessage(
                                id: id,
                                format: .metadata,
                                metadataHeaders: GmailAPIClient.requiredMetadataHeaders
                            )
                        }
                    }
                }
                var result: [GmailMessage] = []
                for try await message in group {
                    result.append(message)
                }
                return result
            }
            details.append(contentsOf: fetched)
        }
        return details.sorted { $0.id < $1.id }
    }

    private func api<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as GmailSyncError {
            throw error
        } catch let error as GmailAPIError {
            throw GmailSyncError.api(error)
        }
    }
}
