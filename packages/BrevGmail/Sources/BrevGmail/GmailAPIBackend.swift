/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import BrevBackend
import Foundation

/// Stable Gmail account identity helpers used by account provisioning.
public enum GmailAccountIdentity {
    /// Returns the durable account key derived from Google's verified OIDC subject.
    public static func accountID(forGoogleSubject subject: String) -> String {
        "gmail-api:\(subject.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

/// Gmail REST adapter behind the provider-neutral `MailBackend` API.
///
/// Gmail labels are projected as folders while message and thread IDs remain
/// account-wide. An injected reconciler keeps the canonical store current on
/// connect and refresh while the typed client handles native mutations,
/// drafts, MIME send, aliases, and signatures.
public final class GmailAPIBackend: MailBackend, MessageLabelManaging, ProviderLabelCatalogManaging,
    ServerSearchSyntaxProviding, MailboxBackgroundRefreshing, SyncHealthReporting,
    MutationApplying, OutboxManaging, SyncConflictManaging, ScheduledSendEditing, @unchecked Sendable {
    private static let pageSize = 50
    private static let maxSearchResults = 5000

    /// The account this adapter serves.
    public let account: BrevAccount

    private let transport: any GmailAPITransporting
    private let store: any GmailAccountStore
    private let client: (any GmailAPIClientProtocol)?
    private let grantedScopes: Set<String>
    private let syncReconciler: GmailSyncReconciler?
    private let draftStaging: any GmailDraftStagingStore
    private let draftOperations = GmailDraftOperationCoordinator()
    private let scheduledDelivery = GmailScheduledDeliveryDriver()
    private var scheduledPollTask: Task<Void, Never>?
    private var scheduledSummary: [PendingScheduledSend] = []
    private var scheduledSummaryRevision = 0
    private var recoveredSchedules = false
    private var scheduledSession: GmailScheduledSession?

    private var scheduledStore: (any GmailScheduledSendStore)? { store as? any GmailScheduledSendStore }
    private let offlineMutationQueue: (any OfflineMutationQueue)?
    private let offlineMutationConflictStore: (any OfflineMutationConflictStore)?
    private let lock = NSLock()
    private var isConnected = false
    private var connectionGeneration = UUID()
    private var profile: GmailProfile?
    private var labelCatalog: [GmailLabel] = []
    private var subscribers: [UUID: AsyncStream<MailEvent>.Continuation] = [:]
    private var lastSyncError: String?
    private var lastSuccessfulSyncAt: Date?
    private var sendAsAliases: [GmailSendAs]?
    private var sendAsProbeCompleted = false
    private var replayConflictCount = 0
    private var refreshedCachedFolders: [Folder.ID: Date] = [:]
    private var cachedFolderRefreshTasks: [Folder.ID: Task<Void, Never>] = [:]

    /// Creates a Gmail API backend with injected REST and canonical-store seams.
    public init(
        account: BrevAccount,
        transport: any GmailAPITransporting,
        store: any GmailAccountStore,
        client: (any GmailAPIClientProtocol)? = nil,
        grantedScopes: Set<String> = [],
        syncReconciler: GmailSyncReconciler? = nil,
        draftStaging: (any GmailDraftStagingStore)? = nil,
        offlineMutationQueue: (any OfflineMutationQueue)? = nil,
        offlineMutationConflictStore: (any OfflineMutationConflictStore)? = nil
    ) {
        self.account = account
        self.transport = transport
        self.store = store
        self.client = client
        self.grantedScopes = grantedScopes
        self.syncReconciler = syncReconciler
        self.draftStaging = draftStaging ?? (store as? any GmailDraftStagingStore) ?? InMemoryGmailDraftStagingStore()
        self.offlineMutationQueue = offlineMutationQueue
        self.offlineMutationConflictStore = offlineMutationConflictStore
    }

    /// Creates a backend using a typed client for Gmail write operations.
    /// Existing read-only callers can continue using the initializer above.
    public convenience init(
        account: BrevAccount,
        transport: any GmailAPITransporting,
        store: any GmailAccountStore,
        client: any GmailAPIClientProtocol,
        grantedScopes: Set<String> = [],
        syncReconciler: GmailSyncReconciler? = nil,
        draftStaging: (any GmailDraftStagingStore)? = nil,
        offlineMutationQueue: (any OfflineMutationQueue)? = nil,
        offlineMutationConflictStore: (any OfflineMutationConflictStore)? = nil
    ) {
        self.init(
            account: account,
            transport: transport,
            store: store,
            client: Optional(client),
            grantedScopes: grantedScopes,
            syncReconciler: syncReconciler,
            draftStaging: draftStaging,
            offlineMutationQueue: offlineMutationQueue,
            offlineMutationConflictStore: offlineMutationConflictStore
        )
    }

    /// Capabilities become available after profile/label discovery succeeds.
    public var capabilities: BackendCapabilities {
        lock.withLock {
            guard isConnected else { return [] }
            var result: BackendCapabilities = [
                .providerAPI,
                .oauthAuth,
                .serverSideSearch,
                .serverSideThreading
            ]
            if !labelCatalog.isEmpty { result.insert(.labels) }
            if profile?.historyID != nil { result.insert(.historyDeltaSync) }
            if sendAsProbeCompleted, sendAsAliases != nil {
                result.insert(.aliases)
                if sendAsAliases?.contains(where: {
                    Self.isUsableSendAs($0) && !($0.signature ?? "").isEmpty
                }) == true {
                    result.insert(.serverSignatures)
                }
            }
            return result
        }
    }

    /// Extended provider capabilities for aliases and server signatures.
    public var extendedCapabilities: BackendExtendedCapabilities {
        lock.withLock {
            guard isConnected else { return [.rawMessageSource, .rawMessageBytes] }
            guard sendAsProbeCompleted, let aliases = sendAsAliases else {
                return [.rawMessageSource, .rawMessageBytes]
            }
            var result: BackendExtendedCapabilities = [.rawMessageSource, .rawMessageBytes, .serverAliases]
            if aliases.contains(where: {
                Self.isUsableSendAs($0) && !($0.signature ?? "").isEmpty
            }) {
                result.insert(.serverSignatures)
            }
            if aliases.contains(where: { Self.isUsableSendAs($0) && $0.isPrimary != true }) {
                result.insert(.sendAs)
            }
            return result
        }
    }

    // MARK: Lifecycle

    public func connect() async throws {
        let generation = lock.withLock { connectionGeneration }
        let draftGeneration = await draftOperations.connectionGeneration()
        do {
            let cachedState = try await store.accountState(accountID: account.id)
            let cachedLabels = try await store.labels(accountID: account.id)
            try lock.withLock {
                guard connectionGeneration == generation else { throw MailBackendError.notConnected }
                if !cachedLabels.isEmpty { labelCatalog = cachedLabels }
                if let cachedState {
                    profile = GmailProfile(emailAddress: cachedState.emailAddress, historyID: cachedState.historyID)
                }
                isConnected = true
            }

            if let syncReconciler {
                try await reconcile(syncReconciler)
                await probeSendAsMetadata()
                try await draftOperations.activate(generation: draftGeneration)
                try requireConnectionGeneration(generation)
                try await prepareScheduledDelivery(generation: generation)
                return
            }
            let fetchedProfile = try await transport.profile()
            let fetchedLabels = try await transport.listLabels()
            let currentState = try await store.accountState(accountID: account.id)
            try requireConnectionGeneration(generation)
            let state = GmailAccountState(
                accountID: account.id,
                emailAddress: fetchedProfile.emailAddress,
                historyID: fetchedProfile.historyID,
                lastFullSyncAt: currentState?.lastFullSyncAt,
                lastDeltaSyncAt: currentState?.lastDeltaSyncAt
            )
            if currentState == nil {
                try await store.replaceSnapshot(
                    GmailAccountSnapshot(
                        accountID: account.id,
                        state: state,
                        labels: fetchedLabels,
                        messages: []
                    )
                )
            } else {
                try await store.apply(GmailStoreDelta(
                    accountID: account.id,
                    upsertedLabels: fetchedLabels,
                    historyID: fetchedProfile.historyID
                ))
            }
            try lock.withLock {
                guard connectionGeneration == generation else { throw MailBackendError.notConnected }
                profile = fetchedProfile
                labelCatalog = fetchedLabels
                isConnected = true
                lastSuccessfulSyncAt = Date()
            }
            await probeSendAsMetadata()
            try await draftOperations.activate(generation: draftGeneration)
            try requireConnectionGeneration(generation)
            try await prepareScheduledDelivery(generation: generation)
        } catch {
            lock.withLock {
                guard connectionGeneration == generation else { return }
                lastSyncError = error.localizedDescription
                isConnected = false
                cachedFolderRefreshTasks.values.forEach { $0.cancel() }
                cachedFolderRefreshTasks.removeAll()
                refreshedCachedFolders.removeAll()
            }
            throw Self.providerNeutralError(error)
        }
    }

    private func requireConnectionGeneration(_ expected: UUID) throws {
        try lock.withLock {
            guard connectionGeneration == expected else { throw MailBackendError.notConnected }
        }
    }

    public func disconnect() async {
        let continuations = lock.withLock { () -> [AsyncStream<MailEvent>.Continuation] in
            isConnected = false
            connectionGeneration = UUID()
            scheduledPollTask?.cancel()
            scheduledPollTask = nil
            recoveredSchedules = false
            if let scheduledSession { GmailScheduledSessionRegistry.shared.retire(scheduledSession, accountID: account.id) }
            scheduledSession = nil
            cachedFolderRefreshTasks.values.forEach { $0.cancel() }
            cachedFolderRefreshTasks.removeAll()
            refreshedCachedFolders.removeAll()
            let values = Array(subscribers.values)
            subscribers.removeAll()
            return values
        }
        await scheduledDelivery.cancel()
        await draftOperations.deactivate()
        continuations.forEach { $0.finish() }
    }

    // MARK: Folders and listing

    public func folders() async throws -> [Folder] {
        try requireConnected()
        let labels = lock.withLock { labelCatalog }
        return Self.folders(from: labels)
    }

    public func refresh(folder: Folder) async throws {
        do {
            if let syncReconciler {
                try await reconcile(syncReconciler)
                return
            }
            let page = try await remoteMessages(in: folder, pageToken: nil)
            emit(.messagesUpdated(folderID: folder.id, messageIDs: page.headers.map(\.id)))
        } catch {
            if !Task.isCancelled, !(error is CancellationError) { recordSyncFailure(error) }
            throw Self.providerNeutralError(error)
        }
    }

    public func applyRetention(folderID: Folder.ID, retentionDays: Int?, keepsBodies: Bool) async {
        await applyRetention(
            folderID: folderID,
            retentionDays: retentionDays,
            keepsBodies: keepsBodies,
            keepingMessageIDs: []
        )
    }

    public func applyRetention(
        folderID: Folder.ID,
        retentionDays: Int?,
        keepsBodies: Bool,
        keepingMessageIDs: Set<MessageHeader.ID>
    ) async {
        guard let cache = readCache else { return }
        if keepsBodies, retentionDays == nil { return }
        let messages: [GmailMessage]
        do {
            messages = try await store.messages(accountID: account.id)
        } catch {
            recordSyncFailure(error)
            return
        }
        let cutoff = retentionDays.map { Date().addingTimeInterval(-Double($0) * 86400) }
        let evicted = Set(messages.compactMap { message -> String? in
            guard message.labelIDs.contains(folderID), !keepingMessageIDs.contains(message.id) else { return nil }
            guard keepsBodies else { return message.id }
            guard let cutoff, let internalDate = message.internalDate,
                  let milliseconds = Double(internalDate)
            else { return nil }
            return Date(timeIntervalSince1970: milliseconds / 1000) < cutoff ? message.id : nil
        })
        guard !evicted.isEmpty else { return }
        do {
            try await cache.removeCachedContent(accountID: account.id, messageIDs: evicted)
        } catch {
            // MailBackend's retention API is intentionally non-throwing. Keep
            // the failure visible through sync health instead of silently
            // claiming that local cache policy was applied.
            recordSyncFailure(error)
        }
    }

    public func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try requireConnected()
        let cacheOffset = pageToken.flatMap { token in
            token.hasPrefix("cached:") ? Int(token.dropFirst("cached:".count)) : nil
        }
        if pageToken == nil || cacheOffset != nil {
            let offset = max(0, cacheOffset ?? 0)
            let cached = try await store.messages(accountID: account.id, labelID: folder.id,
                                                  offset: offset, limit: Self.pageSize + 1)
            let complete = try await store.accountState(accountID: account.id)?.lastFullSyncAt != nil
            if !cached.isEmpty || complete {
                let labels = lock.withLock { labelCatalog }
                let headers = cached.prefix(Self.pageSize).map { Self.header(from: $0, folderID: folder.id, labels: labels) }
                let next = cached.count > Self.pageSize ? "cached:\(offset + Self.pageSize)" : (complete ? nil : "remote:")
                if pageToken == nil { refreshCachedFolderInBackground(folder) }
                return (headers, next)
            }
        }
        return try await remoteMessages(in: folder, pageToken: pageToken == "remote:" ? nil : pageToken)
    }

    private func refreshCachedFolderInBackground(_ folder: Folder) {
        let refreshKey = syncReconciler == nil ? folder.id : "__account__"
        lock.withLock {
            let startedAt = Date()
            guard isConnected, cachedFolderRefreshTasks[refreshKey] == nil,
                  startedAt.timeIntervalSince(refreshedCachedFolders[refreshKey] ?? .distantPast) >= 30 else { return }
            refreshedCachedFolders[refreshKey] = startedAt
            cachedFolderRefreshTasks[refreshKey] = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.lock.withLock {
                        if self.refreshedCachedFolders[refreshKey] == startedAt {
                            self.cachedFolderRefreshTasks.removeValue(forKey: refreshKey)
                        }
                    }
                }
                do { try await refresh(folder: folder) }
                catch { if !Task.isCancelled { recordSyncFailure(error) } }
            }
        }
    }

    private func remoteMessages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try requireConnected()
        let page = try await transport.listMessages(
            labelID: folder.id,
            query: nil,
            pageToken: pageToken,
            maxResults: Self.pageSize,
            includeSpamTrash: folder.role == .spam || folder.role == .trash
        )
        var seen = Set<MessageHeader.ID>()
        let references = page.messages.filter { seen.insert($0.id).inserted }
        let labels = lock.withLock { labelCatalog }
        let headers = try await withThrowingTaskGroup(of: (Int, MessageHeader).self) { group in
            var next = 0
            var results: [Int: MessageHeader] = [:]
            func enqueue(_ index: Int) {
                group.addTask { [self] in
                    let message = try await message(references[index].id)
                    return (index, Self.header(from: message, folderID: folder.id, labels: labels))
                }
            }
            while next < min(4, references.count) {
                enqueue(next); next += 1
            }
            while let (index, header) = try await group.next() {
                try Task.checkCancellation()
                results[index] = header
                if next < references.count { enqueue(next); next += 1 }
            }
            return references.indices.compactMap { results[$0] }
        }
        return (headers, page.nextPageToken)
    }

    public func enumerateMessages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try await remoteMessages(in: folder, pageToken: pageToken)
    }

    // MARK: Read operations

    public func body(for messageID: String) async throws -> MessageBody {
        try requireConnected()
        if let cached = try await readCache?.cachedBody(accountID: account.id, messageID: messageID) {
            if Self.hasBodyContent(cached) { return cached }
        }
        let cachedMessage = try await store.message(accountID: account.id, messageID: messageID)
        let message: GmailMessage
        // A non-nil payload is not enough: label sync stores format=metadata
        // messages whose payload carries only headers. Serving those here
        // returned an empty body with no error, so the reader silently kept
        // the list snippet. Only a payload that yields actual content (or
        // attachments) can satisfy a body read without a full fetch.
        if let cachedMessage, cachedMessage.payload != nil,
           Self.hasBodyContent(Self.body(from: cachedMessage)) {
            message = cachedMessage
        } else {
            let fetched = try await transport.getMessage(messageID: messageID, format: .full)
            try await store.apply(GmailStoreDelta(accountID: account.id, upsertedMessages: [fetched]))
            message = fetched
        }
        let body = Self.body(from: message)
        if message.payload != nil, Self.hasBodyContent(body) {
            try await readCache?.storeBody(body, accountID: account.id)
        }
        return body
    }

    public func rawSource(for messageID: String) async throws -> String {
        if let cached = try await readCache?.cachedRawSource(accountID: account.id, messageID: messageID) {
            return cached
        }
        let data = try await rawMessageData(for: messageID)
        return IMAPMessageBodyParser().rawMessageString(from: data)
    }

    /// Returns original MIME octets, including offline cache reads and legacy-cache repair.
    public func rawMessageData(for messageID: String) async throws -> Data {
        if let cached = try await readCache?.cachedRawMessageData(accountID: account.id, messageID: messageID), !cached.isEmpty {
            return cached
        }
        try requireConnected()
        let message = try await transport.getMessage(messageID: messageID, format: .raw)
        guard let raw = message.raw, let data = Self.decodeBase64URL(raw), !data.isEmpty else {
            throw GmailAPIError.malformedResponse
        }
        try await readCache?.storeRawMessageData(data, accountID: account.id, messageID: messageID)
        return data
    }

    /// Restricts original source access to this Gmail account's own mailbox.
    public func rawMessageData(for messageID: String, sourceID: MailSourceID) async throws -> Data {
        try validateSource(sourceID)
        guard sourceID.mailboxID == account.id else { throw MailBackendError.notFound(id: sourceID.mailboxID) }
        return try await rawMessageData(for: messageID)
    }

    public func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        try requireConnected()
        // The first component is intentionally not interpreted as a URL;
        // Gmail IDs are opaque and can contain URL-significant characters.
        guard let resource = attachment.resource,
              let separator = resource.firstIndex(of: "|") else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        return try await downloadAttachment(
            messageID: String(resource[..<separator]),
            attachmentID: String(resource[resource.index(after: separator)...]),
            cacheID: attachment.id
        )
    }

    /// Reads cached label membership without fetching MIME data or using the primary folder.
    public func cachedMessageHeaders(in folder: Folder, sourceID: MailSourceID) async throws -> [MessageHeader] {
        try validateSource(sourceID)
        guard sourceID.mailboxID == account.id else { throw MailBackendError.notFound(id: sourceID.mailboxID) }
        let labels = try await store.labels(accountID: account.id)
        let cached: [GmailMessage]
        if folder.role == .allMail {
            cached = try await store.messages(accountID: account.id).filter {
                !$0.labelIDs.contains("TRASH") && !$0.labelIDs.contains("SPAM")
            }
        } else {
            cached = try await store.messages(accountID: account.id, labelID: folder.id, offset: 0, limit: Int.max)
        }
        return cached.map { Self.header(from: $0, folderID: folder.id, labels: labels) }
    }

    public func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        try requireConnected()
        if query.execution == .cacheOnly {
            let cached = try await store.messages(accountID: account.id)
            return cached
                .filter { query.matches(Self.header(
                    from: $0,
                    folderID: Self.primaryFolderID(for: $0, labels: labelCatalog),
                    labels: labelCatalog
                )) }
                .map { Self.header(from: $0, folderID: Self.primaryFolderID(for: $0, labels: labelCatalog), labels: labelCatalog)
                }
        }
        var result: [MessageHeader] = []
        var seen = Set<MessageHeader.ID>()
        var pageToken: String?
        var visitedPageTokens = Set<String>()
        let search = Self.searchScope(for: query, labels: labelCatalog)
        repeat {
            let page = try await transport.listMessages(
                labelID: search.labelID,
                query: search.query,
                pageToken: pageToken,
                maxResults: min(Self.pageSize, Self.maxSearchResults - result.count),
                includeSpamTrash: search.includeSpamTrash
            )
            for reference in page.messages {
                guard result.count < Self.maxSearchResults,
                      seen.insert(reference.id).inserted else { continue }
                let message = try await message(reference.id)
                result.append(Self.header(
                    from: message,
                    folderID: Self.primaryFolderID(for: message, labels: labelCatalog),
                    labels: labelCatalog
                ))
            }
            guard let nextPageToken = page.nextPageToken,
                  visitedPageTokens.insert(nextPageToken).inserted,
                  result.count < Self.maxSearchResults
            else {
                pageToken = nil
                continue
            }
            pageToken = nextPageToken
        } while pageToken != nil
        return result
    }

    // MARK: Drafts, send, and provider identities

    public func save(draft: Draft) async throws -> Draft {
        try requireConnected()
        try validateDraftID(draft)
        return try await draftOperations.withOperation(identifiers: [draft.id, draft.remoteID ?? ""]) { lease in
            try await self.performSave(draft: draft, lease: lease)
        }
    }

    private func performSave(draft: Draft, lease: GmailDraftOperationCoordinator.Lease) async throws -> Draft {
        try await draftOperations.withStaging(lease) { try await self.draftStaging.setDraft(draft, accountID: self.account.id) }
        let MIME = try await MIMEMessageBuilder(
            draft: draft,
            from: sender(for: draft),
            attachments: stagedMIMEAttachments(for: draft)
        ).build()
        try await draftOperations.check(lease)
        let remote: GmailDraft
        if let remoteID = draft.remoteID {
            remote = try await transport.updateDraft(
                id: remoteID,
                rawMIME: String(decoding: MIME, as: UTF8.self),
                threadID: draft.threadID
            )
        } else {
            remote = try await transport.createDraft(
                rawMIME: String(decoding: MIME, as: UTF8.self),
                threadID: draft.threadID
            )
        }
        var saved = draft
        saved.remoteID = remote.id
        // Preserve the confirmed remote identity so a local failure cannot make
        // the composer retry this as a new provider draft.
        let acknowledged = saved
        do {
            try await draftOperations.withStaging(lease) {
                try await self.draftStaging.setDraft(acknowledged, accountID: self.account.id)
            }
        } catch { recordSyncFailure(error) }
        return saved
    }

    public func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        try requireConnected()
        let attachment = GmailStagedAttachment(
            id: "gmail-stage-" + UUID().uuidString,
            draftID: draftID,
            filename: filename,
            mimeType: mimeType,
            data: data
        )
        try await draftOperations.withOperation(identifiers: [draftID]) { lease in
            try await self.draftOperations.withStaging(lease) {
                try await self.draftStaging.setAttachment(attachment, accountID: self.account.id)
            }
        }
        return attachment.id
    }

    public func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> String {
        try requireConnected()
        let attachment = GmailStagedAttachment(
            id: "gmail-inline-" + UUID().uuidString,
            draftID: draftID,
            filename: filename,
            mimeType: mimeType,
            data: data,
            isInline: true,
            contentID: contentID
        )
        try await draftOperations.withOperation(identifiers: [draftID]) { lease in
            try await self.draftOperations.withStaging(lease) {
                try await self.draftStaging.setAttachment(attachment, accountID: self.account.id)
            }
        }
        return attachment.id
    }

    public func discard(draftID: String) async throws {
        try requireConnected()
        let stored = try await draftStaging.draft(accountID: account.id, draftID: draftID)
        try await draftOperations.withOperation(identifiers: [draftID, stored?.id ?? "", stored?.remoteID ?? ""]) { lease in
            try await self.performDiscard(draftID: draftID, lease: lease)
        }
    }

    private func performDiscard(draftID: String, lease: GmailDraftOperationCoordinator.Lease) async throws {
        let stored = try await draftStaging.draft(accountID: account.id, draftID: draftID)
        if let scheduledStore,
           try await scheduledStore.scheduledDraft(accountID: account.id, draftID: stored?.id ?? draftID) != nil {
            throw GmailScheduledSendError.inFlight
        }
        try await draftOperations.check(lease)
        if let remoteID = stored?.remoteID ?? (stored == nil ? draftID : nil) {
            do { try await transport.deleteDraft(id: remoteID) }
            catch GmailAPIError.httpFailure(statusCode: 404) {
                // A prior discard may have succeeded remotely before local cleanup failed.
            }
        }
        try await draftOperations.withStaging(lease) {
            try await self.draftStaging.removeDraft(accountID: self.account.id, draftID: draftID)
        }
    }

    public func send(draft: Draft) async throws -> SendResult {
        try requireConnected()
        try validateSendDraft(draft)
        return try await draftOperations.withOperation(identifiers: [draft.id, draft.remoteID ?? ""]) { lease in
            if draft.scheduledFor != nil { return try await self.schedule(draft: draft, lease: lease) }
            return try await self.performSend(draft: draft, lease: lease)
        }
    }

    private func performSend(draft: Draft, lease: GmailDraftOperationCoordinator.Lease) async throws -> SendResult {
        if let scheduledStore, try await scheduledStore.scheduledDraft(accountID: account.id, draftID: draft.id) != nil {
            throw GmailScheduledSendError.inFlight
        }
        try await draftOperations.withStaging(lease) { try await self.draftStaging.setDraft(draft, accountID: self.account.id) }
        try await draftOperations.check(lease)
        let sent: GmailMessage
        do {
            if let remoteID = draft.remoteID {
                sent = try await transport.sendDraft(id: remoteID)
            } else {
                let MIME = try await MIMEMessageBuilder(
                    draft: draft,
                    from: sender(for: draft),
                    attachments: stagedMIMEAttachments(for: draft)
                ).build()
                try await draftOperations.check(lease)
                sent = try await transport.sendMessage(
                    rawMIME: String(decoding: MIME, as: UTF8.self),
                    threadID: draft.threadID
                )
            }
        } catch let error as GmailAPIError where error.isAmbiguousSend {
            // Keep the staged draft and attachments. Delivery may have occurred.
            throw error
        }
        // A local cleanup failure must not turn a confirmed send into a retryable send error.
        do {
            try await draftOperations.withStaging(lease) {
                try await self.draftStaging.removeDraft(accountID: self.account.id, draftID: draft.id)
            }
        } catch { recordSyncFailure(error) }
        return SendResult(sentMessageID: sent.id)
    }

    private func schedule(draft: Draft, lease: GmailDraftOperationCoordinator.Lease) async throws -> SendResult {
        guard let scheduledStore else { throw unsupported() }
        try await draftOperations.withStaging(lease) { try await self.draftStaging.setDraft(draft, accountID: self.account.id) }
        let mime = try await MIMEMessageBuilder(draft: draft, from: sender(for: draft),
                                                attachments: stagedMIMEAttachments(for: draft)).build()
        try await draftOperations.withStaging(lease) {
            try await scheduledStore.enqueueScheduledSend(draft, rawMIME: mime, accountID: self.account.id)
        }
        do { try await reloadScheduledSummary() } catch { recordSyncFailure(error) }
        return SendResult(sentMessageID: nil, scheduledFor: draft.scheduledFor)
    }

    /// Cached metadata supports the synchronous native quit warning without reading MIME content.
    public func pendingScheduledSends() -> [PendingScheduledSend] { lock.withLock { scheduledSummary } }

    /// Concurrent poller/background/manual requests join one delivery pass.
    public func deliverDueScheduledSends() async {
        await scheduledDelivery.run { [weak self] in await self?.deliverScheduledBatch() }
    }

    /// Returns the explicitly submitted content, not a later autosave.
    public func scheduledDraft(id: String) async throws -> Draft {
        guard let scheduledStore, let draft = try await scheduledStore.scheduledDraft(accountID: account.id, draftID: id) else {
            throw GmailScheduledSendError.notFound
        }
        return draft
    }

    /// Withdraws the schedule and preserves content for editing.
    public func cancelScheduledSend(id: String) async throws -> Draft? {
        guard let scheduledStore else { throw unsupported() }
        let original = try await scheduledDraft(id: id)
        let draft = try await draftOperations.withOperation(identifiers: [id, original.remoteID ?? ""]) { lease in
            try await self.draftOperations.withStaging(lease) {
                try await scheduledStore.cancelScheduledSend(accountID: self.account.id, draftID: id)
            }
        }
        do { try await reloadScheduledSummary() } catch { recordSyncFailure(error) }
        return draft
    }

    /// Reschedules frozen content following an explicit user request.
    public func rescheduleSend(id: String, for date: Date) async throws {
        try await changeScheduledTime(id: id, date: date, allowReview: false)
    }

    /// Retries uncertain delivery only through an explicit reviewed action.
    public func retryReviewedScheduledSend(id: String, for date: Date) async throws {
        try await changeScheduledTime(id: id, date: date, allowReview: true)
    }

    private func changeScheduledTime(id: String, date: Date, allowReview: Bool) async throws {
        guard let scheduledStore else { throw unsupported() }
        let original = try await scheduledDraft(id: id)
        try await draftOperations.withOperation(identifiers: [id, original.remoteID ?? ""]) { lease in
            try await self.draftOperations.withStaging(lease) {
                try await scheduledStore.rescheduleSend(
                    accountID: self.account.id,
                    draftID: id,
                    date: date,
                    allowReview: allowReview
                )
            }
        }
        do { try await reloadScheduledSummary() } catch { recordSyncFailure(error) }
    }

    private func prepareScheduledDelivery(generation: UUID) async throws {
        guard let scheduledStore else { return }
        if !lock.withLock({ recoveredSchedules }) {
            try await draftOperations.withOperation(identifiers: []) { lease in
                try await self.draftOperations.withStaging(lease) {
                    try await scheduledStore.recoverInterruptedScheduledSends(accountID: self.account.id) {
                        GmailScheduledSessionRegistry.shared.activeIDs(accountID: self.account.id)
                    }
                }
            }
        }
        try await reloadScheduledSummary()
        try lock.withLock {
            guard connectionGeneration == generation else { throw MailBackendError.notConnected }
            if scheduledSession == nil { scheduledSession = GmailScheduledSessionRegistry.shared.register(accountID: account.id) }
            recoveredSchedules = true
            guard scheduledPollTask == nil else { return }
            scheduledPollTask = Task { [weak self] in
                await self?.deliverDueScheduledSends()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    await deliverDueScheduledSends()
                }
            }
        }
    }

    private func reloadScheduledSummary() async throws {
        guard let scheduledStore else { return }
        let request = lock.withLock { () -> (Int, UUID) in
            scheduledSummaryRevision += 1
            return (scheduledSummaryRevision, connectionGeneration)
        }
        let values = try await scheduledStore.scheduledSends(accountID: account.id)
        let changed = lock.withLock { () -> Bool in
            guard scheduledSummaryRevision == request.0, connectionGeneration == request.1 else { return false }
            let changed = scheduledSummary != values
            scheduledSummary = values
            return changed
        }
        if changed { emit(.outboxChanged) }
    }

    private func deliverScheduledBatch() async {
        guard let scheduledStore, lock.withLock({ isConnected }), !Task.isCancelled else { return }
        do {
            let ownID = lock.withLock { scheduledSession?.id }
            try await draftOperations.withOperation(identifiers: []) { lease in
                try await self.draftOperations.withStaging(lease) {
                    try await scheduledStore.recoverInterruptedScheduledSends(accountID: self.account.id) {
                        var owners = GmailScheduledSessionRegistry.shared.activeIDs(accountID: self.account.id)
                        if let ownID { owners.remove(ownID) }
                        return owners
                    }
                }
            }
            try await reloadScheduledSummary()
            let now = Date()
            let due = pendingScheduledSends().filter {
                $0.state == .waiting && $0.scheduledFor <= now && ($0.nextAttemptAt.map { $0 <= now } ?? true)
            }
            for entry in due {
                try Task.checkCancellation()
                let snapshot = try await scheduledDraft(id: entry.draftID)
                do {
                    try await draftOperations.withOperation(identifiers: [snapshot.id, snapshot.remoteID ?? ""]) { lease in
                        guard let ownerID = self.lock.withLock({ self.scheduledSession?.id })
                        else { throw MailBackendError.notConnected }
                        guard let attempt = try await self.draftOperations.withStaging(lease, operation: {
                            try await scheduledStore.claimScheduledSend(
                                accountID: self.account.id,
                                draftID: snapshot.id,
                                now: Date(),
                                ownerID: ownerID
                            )
                        }) else { return }
                        do { try await self.reloadScheduledSummary() } catch { self.recordSyncFailure(error) }
                        try await self.draftOperations.check(lease)
                        do {
                            try self.validateSendDraft(attempt.draft)
                            let source = try GmailScheduledMIME.source(attempt.rawMIME, sentAt: Date())
                            let result = try await self.transport.sendMessage(rawMIME: source,
                                                                              threadID: attempt.draft.threadID)
                            guard !result.id.isEmpty else { throw GmailAPIError.malformedResponse }
                        } catch {
                            let retryAt = GmailScheduledRetryPolicy.retryDate(
                                for: error,
                                attempt: attempt.attemptCount,
                                now: Date()
                            )
                            try await self.draftOperations.withStaging(lease) {
                                try await scheduledStore.failScheduledSend(accountID: self.account.id, draftID: snapshot.id,
                                                                           attemptID: attempt.attemptID,
                                                                           message: error.localizedDescription, retryAt: retryAt)
                            }
                            return
                        }
                        // Once sent, local failure leaves a non-retryable delivering record for recovery.
                        let canRemoveProviderDraft: Bool
                        do {
                            canRemoveProviderDraft = try await self.draftOperations.withStaging(lease) {
                                try await scheduledStore.completeScheduledSend(accountID: self.account.id, draftID: snapshot.id,
                                                                               attemptID: attempt.attemptID)
                            }
                        } catch {
                            self.recordSyncFailure(error)
                            let message = String(
                                localized: "Gmail confirmed delivery, but local cleanup failed. Check Sent before removing this schedule.",
                                bundle: .module
                            )
                            try await self.draftOperations.withStaging(lease) {
                                try await scheduledStore.failScheduledSend(accountID: self.account.id, draftID: snapshot.id,
                                                                           attemptID: attempt.attemptID, message: message,
                                                                           retryAt: nil)
                            }
                            return
                        }
                        if canRemoveProviderDraft, let remoteID = attempt.draft.remoteID {
                            try await self.draftOperations.check(lease)
                            do { try await self.transport.deleteDraft(id: remoteID) }
                            catch GmailAPIError.httpFailure(statusCode: 404) {}
                            catch { self.recordSyncFailure(error) }
                        }
                    }
                } catch GmailDraftOperationError.busy {
                    continue // A composer owns the draft; leave its unclaimed schedule for the next tick.
                }
            }
            try await reloadScheduledSummary()
        } catch {
            if !Task.isCancelled { recordSyncFailure(error) }
        }
    }

    /// Returns existing Gmail send-as identities.
    public func listAliases() async throws -> [ServerAlias] {
        try requireConnected()
        let aliases = try await loadSendAs()
        return aliases.filter(Self.isUsableSendAs).map { alias in
            ServerAlias(
                id: alias.sendAsEmail,
                email: alias.sendAsEmail,
                displayName: alias.displayName,
                isDefault: alias.isDefault == true
            )
        }
    }

    /// Maps Gmail's per-alias HTML signatures into provider-neutral signatures.
    public func listServerSignatures() async throws -> [ServerSignature] {
        try requireConnected()
        return try await loadSendAs().filter(Self.isUsableSendAs).compactMap { alias in
            guard let signature = alias.signature, !signature.isEmpty else { return nil }
            return ServerSignature(
                id: alias.sendAsEmail,
                name: alias.displayName ?? alias.sendAsEmail,
                body: signature,
                isDefault: alias.isDefault == true
            )
        }
    }

    // MARK: Native message mutations

    public func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        let add = isRead ? [] : ["UNREAD"]
        let remove = isRead ? ["UNREAD"] : []
        do { try await applyLabelMutation(messageIDs: messageIDs, add: add, remove: remove) }
        catch { guard await enqueueIfRetryable(.setRead(isRead), messageIDs: messageIDs, error: error) else { throw error } }
    }

    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        let add = isFlagged ? ["STARRED"] : []
        let remove = isFlagged ? [] : ["STARRED"]
        do { try await applyLabelMutation(messageIDs: messageIDs, add: add, remove: remove) }
        catch { guard await enqueueIfRetryable(.setFlagged(isFlagged), messageIDs: messageIDs, error: error) else { throw error }
        }
    }

    public func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws {
        let add = isJunk ? ["SPAM"] : ["INBOX"]
        let remove = isJunk ? ["INBOX"] : ["SPAM"]
        do { try await applyLabelMutation(messageIDs: messageIDs, add: add, remove: remove) }
        catch { guard await enqueueIfRetryable(.setJunk(isJunk), messageIDs: messageIDs, error: error) else { throw error } }
    }

    /// Captures the label delta for this move so Undo preserves unrelated labels.
    public func moveWithUndo(messageIDs: [MessageHeader.ID], from sourceFolder: Folder, to destination: Folder,
                             sourceID: MailSourceID) async throws -> MailMoveUndo? {
        try validateSource(sourceID)
        guard sourceID.mailboxID == account.id else { throw MailBackendError.notFound(id: sourceID.mailboxID) }
        guard !messageIDs.isEmpty, sourceFolder.id != destination.id else { return nil }
        var originals: [String: Set<String>] = [:]
        for id in messageIDs {
            originals[id] = try await Set(canonicalMessage(id).labelIDs)
        }
        do { try await performMove(messageIDs: messageIDs, to: destination) }
        catch {
            if await enqueueIfRetryable(.move(folderID: destination.id), messageIDs: messageIDs, error: error) { return nil }
            throw error
        }
        let capturedLabels = originals
        let progress = GmailMoveUndoProgress()
        let changes = Self.moveLabelChanges(to: destination)
        return MailMoveUndo(sourceID: sourceID, originalFolder: sourceFolder) { [self] in
            try requireConnected()
            guard let client else { throw unsupported() }
            try await progress.restore(messageIDs) { id in
                let original = capturedLabels[id] ?? []
                var add = original.intersection(changes.remove)
                var remove = Set(changes.add).subtracting(original)
                if remove.remove("TRASH") != nil {
                    _ = try await client.untrashMessage(id: id)
                    if !original.contains("INBOX") { remove.insert("INBOX") }
                }
                try Task.checkCancellation()
                if add.remove("TRASH") != nil { _ = try await client.trashMessage(id: id) }
                try Task.checkCancellation()
                if !add.isEmpty || !remove.isEmpty {
                    _ = try await client.modifyMessageLabels(id: id, addLabelIDs: add.sorted(), removeLabelIDs: remove.sorted())
                }
            }
            try await refreshStoredMessages(messageIDs)
            return Dictionary(messageIDs.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private static func moveLabelChanges(to folder: Folder) -> (add: [String], remove: [String]) {
        if folder.role == .trash || folder.id.uppercased() == "TRASH" { return (["TRASH"], ["INBOX"]) }
        let remove = folder.role == .inbox || folder.id.uppercased() == "INBOX"
            ? ["TRASH", "SPAM"] : ["INBOX", "TRASH", "SPAM"]
        let add = folder.role == .allMail || folder.id.uppercased() == "ALL_MAIL" ? [] : [folder.id]
        return (add, remove)
    }

    public func move(messageIDs: [String], to folder: Folder) async throws {
        do { try await performMove(messageIDs: messageIDs, to: folder) }
        catch {
            guard await enqueueIfRetryable(.move(folderID: folder.id), messageIDs: messageIDs, error: error) else { throw error }
        }
    }

    private func performMove(messageIDs: [String], to folder: Folder) async throws {
        guard let client else { throw unsupported() }
        try requireConnected()
        if folder.role == .trash || folder.id.uppercased() == "TRASH" {
            for messageID in messageIDs {
                _ = try await client.trashMessage(id: messageID)
            }
            try await refreshStoredMessages(messageIDs)
            return
        }
        for messageID in messageIDs {
            let current = try await canonicalMessage(messageID)
            if current.labelIDs.contains("TRASH") {
                _ = try await client.untrashMessage(id: messageID)
            }
            let changes = Self.moveLabelChanges(to: folder)
            _ = try await client.modifyMessageLabels(
                id: messageID, addLabelIDs: changes.add, removeLabelIDs: changes.remove
            )
        }
        try await refreshStoredMessages(messageIDs)
    }

    public func delete(messageIDs: [String]) async throws {
        var includesPermanentDelete = false
        for messageID in messageIDs {
            if try await canonicalMessage(messageID).labelIDs.contains("TRASH") {
                includesPermanentDelete = true
                break
            }
        }
        do { try await performDelete(messageIDs: messageIDs) }
        catch {
            guard !includesPermanentDelete,
                  await enqueueIfRetryable(.delete, messageIDs: messageIDs, error: error)
            else { throw error }
        }
    }

    private func performDelete(messageIDs: [String]) async throws {
        guard let client else { throw unsupported() }
        try requireConnected()
        for messageID in messageIDs {
            let current = try await canonicalMessage(messageID)
            if current.labelIDs.contains("TRASH") {
                guard grantedScopes.contains("https://mail.google.com/") else {
                    throw MailBackendError.notSupported(.providerAPI)
                }
                try await client.deleteMessage(id: messageID)
                try await store.apply(GmailStoreDelta(accountID: account.id, removedMessageIDs: [messageID]))
            } else {
                _ = try await client.trashMessage(id: messageID)
                try await refreshStoredMessages([messageID])
            }
        }
    }

    // MARK: MessageLabelManaging

    public func setLabels(
        _ labels: [String],
        isEnabled: Bool,
        for messageIDs: [MessageHeader.ID],
        sourceID: MailSourceID?
    ) async throws {
        try validateSource(sourceID)
        let labelIDs = try labels.map(resolveLabelID)
        do {
            try await applyLabelMutation(
                messageIDs: messageIDs,
                add: isEnabled ? labelIDs : [],
                remove: isEnabled ? [] : labelIDs
            )
        } catch {
            // Persist immutable Gmail IDs, never mutable display names, so a
            // renamed label still replays against the intended target.
            guard await enqueueIfRetryable(.setLabels(labelIDs, isEnabled: isEnabled), messageIDs: messageIDs, error: error)
            else { throw error }
        }
    }

    // MARK: Provider label catalog

    public func labelCatalog(for sourceID: MailSourceID) async throws -> [ProviderLabel] {
        try validateSource(sourceID)
        try requireConnected()
        return lock.withLock { labelCatalog.map { Self.providerLabel(from: $0, labels: labelCatalog) } }
    }

    public func createLabel(name: String, parentID: String?, sourceID: MailSourceID) async throws -> ProviderLabel {
        try validateSource(sourceID)
        guard let client else { throw unsupported() }
        try requireConnected()
        let fullName = Self.fullLabelName(name: name, parentID: parentID, labels: labelCatalog)
        let created = try await client.createLabel(GmailLabelWrite(name: fullName))
        try await store.apply(GmailStoreDelta(accountID: account.id, upsertedLabels: [created]))
        updateLabelCatalog(created)
        return Self.providerLabel(from: created, labels: lock.withLock { labelCatalog })
    }

    public func renameLabel(id: String, name: String, sourceID: MailSourceID) async throws -> ProviderLabel {
        try validateSource(sourceID)
        guard let client else { throw unsupported() }
        let current = try label(id: id)
        guard current.type == "user" else { throw unsupported() }
        let renamed = Self.fullLabelName(
            name: name,
            parentID: Self.parentID(for: current, labels: labelCatalog),
            labels: labelCatalog
        )
        let updated = try await client.patchLabel(id: id, with: GmailLabelWrite(name: renamed))
        try await store.apply(GmailStoreDelta(accountID: account.id, upsertedLabels: [updated]))
        updateLabelCatalog(updated)
        return Self.providerLabel(from: updated, labels: lock.withLock { labelCatalog })
    }

    public func deleteLabel(id: String, sourceID: MailSourceID) async throws {
        try validateSource(sourceID)
        guard let client else { throw unsupported() }
        let current = try label(id: id)
        guard current.type == "user" else { throw unsupported() }
        try await client.deleteLabel(id: id)
        try await store.apply(GmailStoreDelta(accountID: account.id, removedLabelIDs: [id]))
        lock.withLock { labelCatalog.removeAll { $0.id == id } }
    }

    public func updateLabel(
        id: String,
        visibility: ProviderLabelVisibility?,
        color: ProviderLabelColor?,
        sourceID: MailSourceID
    ) async throws -> ProviderLabel {
        try validateSource(sourceID)
        guard let client else { throw unsupported() }
        let current = try label(id: id)
        guard current.type == "user" else { throw unsupported() }
        let write = GmailLabelWrite(
            labelListVisibility: visibility.map(Self.gmailListVisibility),
            messageListVisibility: visibility.map(Self.gmailMessageVisibility),
            color: color.map { GmailLabelColor(textColor: $0.foregroundHex, backgroundColor: $0.backgroundHex) }
        )
        let updated = try await client.patchLabel(id: id, with: write)
        try await store.apply(GmailStoreDelta(accountID: account.id, upsertedLabels: [updated]))
        updateLabelCatalog(updated)
        return Self.providerLabel(from: updated, labels: lock.withLock { labelCatalog })
    }

    public func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        _ = attachmentID; throw unsupported()
    }

    public func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
        _ = messageID; _ = response; throw unsupported()
    }

    public func subscribeToChanges() -> AsyncStream<MailEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { subscribers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                _ = self?.lock.withLock { self?.subscribers.removeValue(forKey: id) }
            }
        }
    }

    public func extensionService<Service>(_ type: Service.Type) -> Service? {
        switch ObjectIdentifier(type) {
        case ObjectIdentifier(ScheduledSendManaging.self), ObjectIdentifier(ScheduledSendEditing.self):
            guard scheduledStore != nil else { return nil }
            return self as? Service
        case ObjectIdentifier(MessageLabelManaging.self):
            guard client != nil else { return nil }
            return self as? Service
        case ObjectIdentifier(ProviderLabelCatalogManaging.self):
            return self as? Service
        case ObjectIdentifier(ServerSearchSyntaxProviding.self):
            return self as? Service
        case ObjectIdentifier(MailboxBackgroundRefreshing.self),
             ObjectIdentifier(SyncHealthReporting.self):
            return self as? Service
        case ObjectIdentifier(OutboxManaging.self),
             ObjectIdentifier(SyncConflictManaging.self):
            guard offlineMutationQueue != nil else { return nil }
            return self as? Service
        default:
            return nil
        }
    }

    public func refreshMailbox(for sourceID: MailSourceID) async throws {
        try validateSource(sourceID)
        guard let syncReconciler else { throw unsupported() }
        try await reconcile(syncReconciler)
    }

    public func syncHealth(for sourceID: MailSourceID) async -> AccountSyncHealth {
        let state: GmailAccountState? = try? await store.accountState(accountID: account.id)
        let error = lock.withLock { lastSyncError }
        let successfulAt = lock.withLock { lastSuccessfulSyncAt }
            ?? state?.lastDeltaSyncAt
            ?? state?.lastFullSyncAt
        let pendingCount = await (try? offlineMutationQueue?.pending().count) ?? 0
        let conflicts = await (try? offlineMutationConflictStore?.conflicts().count) ?? 0
        let healthState: SyncHealthState = error == nil ? .healthy : .providerError
        return AccountSyncHealth(
            sourceID: sourceID,
            state: healthState,
            lastSuccessfulSyncAt: successfulAt,
            lastErrorDescription: error,
            indexStatus: .notBuilt,
            cacheSizeBytes: 0,
            pendingMutationCount: pendingCount,
            replayConflictCount: conflicts
        )
    }

    public func replayOfflineMutations() async {
        guard let queue = offlineMutationQueue else { return }
        guard let items = try? await queue.pending() else { return }
        for mutation in items {
            do {
                try await apply(mutation)
                try await queue.remove(id: mutation.id)
            } catch let error as MailBackendError {
                if isPermanentReplayError(error) {
                    await recordConflict(mutation, message: error.localizedDescription)
                    try? await queue.remove(id: mutation.id)
                    continue
                }
                break
            } catch let error as GmailAPIError {
                guard isPermanentReplayError(error) else { break }
                await recordConflict(mutation, message: error.localizedDescription)
                try? await queue.remove(id: mutation.id)
            } catch {
                break
            }
        }
    }

    public func pendingMutations() async -> [PendingMutation] {
        await (try? offlineMutationQueue?.pending()) ?? []
    }

    public func discardMutation(id: UUID) async {
        try? await offlineMutationQueue?.remove(id: id)
    }

    public func discardAllMutations() async {
        try? await offlineMutationQueue?.removeAll()
    }

    public func replayConflicts(for sourceID: MailSourceID) async -> [ReplayConflict] {
        guard sourceID.accountID == account.id else { return [] }
        let conflicts = await (try? offlineMutationConflictStore?.conflicts()) ?? []
        return conflicts.map {
            ReplayConflict(
                id: $0.id,
                folderName: account.emailAddress,
                operationDescription: $0.mutation.kind.operationDescription,
                failureReason: $0.message,
                detectedAt: $0.detectedAt
            )
        }
    }

    public func dismissConflict(id: UUID, sourceID: MailSourceID) async {
        guard sourceID.accountID == account.id else { return }
        try? await offlineMutationConflictStore?.remove(id: id)
    }

    public func dismissAllConflicts(for sourceID: MailSourceID) async {
        guard sourceID.accountID == account.id else { return }
        try? await offlineMutationConflictStore?.removeAll()
    }

    // MARK: Private helpers

    private var readCache: (any GmailReadCacheStore)? {
        store as? (any GmailReadCacheStore)
    }

    private func validateDraftID(_ draft: Draft) throws {
        guard !draft.id.isEmpty else { throw GmailAPIError.invalidRequest }
    }

    private func validateSendDraft(_ draft: Draft) throws {
        try validateDraftID(draft)
        guard draft.securityMode == .none else { throw OutboundCryptoEngineUnavailableError(mode: draft.securityMode) }
        guard !(draft.to + draft.cc + draft.bcc).isEmpty else {
            throw DraftValidationError.missingRecipients
        }
    }

    private func stagedMIMEAttachments(for draft: Draft) async throws -> [MIMEMessageAttachment] {
        var result: [MIMEMessageAttachment] = []
        for attachmentID in draft.attachmentIDs {
            guard let attachment = try await draftStaging.attachment(
                accountID: account.id,
                attachmentID: attachmentID
            ) else {
                throw MailBackendError.notFound(id: attachmentID)
            }
            result.append(MIMEMessageAttachment(
                id: attachment.id,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                data: attachment.data,
                isInline: attachment.isInline,
                contentID: attachment.contentID
            ))
        }
        return result
    }

    private func sender(for draft: Draft) async throws -> Correspondent {
        let aliases: [GmailSendAs]
        do {
            aliases = try await loadSendAs()
        } catch {
            guard draft.identityID == nil else { throw error }
            return Correspondent(email: account.emailAddress)
        }
        if let identityID = draft.identityID,
           let alias = aliases.first(where: { Self.isUsableSendAs($0) && $0.sendAsEmail == identityID }) {
            return Correspondent(name: alias.displayName, email: alias.sendAsEmail)
        }
        if let primary = aliases.first(where: { Self.isUsableSendAs($0) && $0.isPrimary == true }) {
            return Correspondent(name: primary.displayName, email: primary.sendAsEmail)
        }
        return Correspondent(email: account.emailAddress)
    }

    private func loadSendAs() async throws -> [GmailSendAs] {
        if let cached = lock.withLock({ sendAsAliases }) { return cached }
        guard hasSendAsScope else { throw MailBackendError.notSupported(.aliases) }
        let fetched = try await transport.listSendAs()
        lock.withLock {
            sendAsAliases = fetched
            sendAsProbeCompleted = true
        }
        return fetched
    }

    /// Probes send-as metadata during connect so capabilities describe the
    /// account's actual grants and Workspace policy rather than optimistic UI.
    private func probeSendAsMetadata() async {
        guard hasSendAsScope else {
            lock.withLock { sendAsProbeCompleted = true; sendAsAliases = nil }
            return
        }
        do {
            let fetched = try await transport.listSendAs()
            lock.withLock {
                sendAsAliases = fetched
                sendAsProbeCompleted = true
            }
        } catch {
            lock.withLock {
                sendAsAliases = nil
                sendAsProbeCompleted = true
            }
        }
    }

    private var hasSendAsScope: Bool {
        grantedScopes.contains("https://mail.google.com/")
            || grantedScopes.contains("https://www.googleapis.com/auth/gmail.settings.basic")
    }

    private static func isUsableSendAs(_ alias: GmailSendAs) -> Bool {
        guard alias.isPrimary != true else { return true }
        guard let status = alias.verificationStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty
        else { return true }
        return status.caseInsensitiveCompare("accepted") == .orderedSame
    }

    private func requireConnected() throws {
        guard lock.withLock({ isConnected }) else { throw MailBackendError.notConnected }
    }

    public func apply(_ mutation: PendingMutation) async throws {
        guard mutation.sourceID?.accountID == nil || mutation.sourceID?.accountID == account.id else {
            throw MailBackendError.notFound(id: account.id)
        }
        switch mutation.kind {
        case .setRead(let value):
            try await applyLabelMutation(
                messageIDs: mutation.messageIDs,
                add: value ? [] : ["UNREAD"],
                remove: value ? ["UNREAD"] : []
            )
        case .setFlagged(let value):
            try await applyLabelMutation(
                messageIDs: mutation.messageIDs,
                add: value ? ["STARRED"] : [],
                remove: value ? [] : ["STARRED"]
            )
        case .move(let folderID):
            guard let folder = try? await folders().first(where: { $0.id == folderID })
            else { throw MailBackendError.notFound(id: folderID) }
            try await performMove(messageIDs: mutation.messageIDs, to: folder)
        case .setJunk(let value):
            try await applyLabelMutation(
                messageIDs: mutation.messageIDs,
                add: value ? ["SPAM"] : ["INBOX"],
                remove: value ? ["INBOX"] : ["SPAM"]
            )
        case .setLabels(let labels, let isEnabled):
            let ids = try labels.map(resolveLabelID)
            try await applyLabelMutation(messageIDs: mutation.messageIDs, add: isEnabled ? ids : [], remove: isEnabled ? [] : ids)
        case .delete:
            guard let client else { throw unsupported() }
            for id in mutation.messageIDs {
                _ = try await client.trashMessage(id: id)
            }
            try await refreshStoredMessages(mutation.messageIDs)
        case .setFlagColor, .copy, .send, .sendStagedDraft:
            throw MailBackendError.notSupported(.providerAPI)
        }
    }

    private func enqueueIfRetryable(
        _ kind: PendingMutation.Kind,
        messageIDs: [String],
        error: Error
    ) async -> Bool {
        guard shouldQueue(error), let queue = offlineMutationQueue else { return false }
        let sourceID = MailSourceID(accountID: account.id, mailboxID: account.id)
        return await (try? queue.enqueue(PendingMutation(kind: kind, sourceID: sourceID, messageIDs: messageIDs))) != nil
    }

    private func shouldQueue(_ error: Error) -> Bool {
        if let error = error as? GmailAPIError {
            return error == .transportFailure || error.isRetryable
        }
        guard let error = error as? MailBackendError else { return false }
        switch error {
        case .notConnected, .network, .rateLimited: return true
        default: return false
        }
    }

    private func isPermanentReplayError(_ error: MailBackendError) -> Bool {
        switch error {
        case .notFound, .permissionDenied, .quotaExceeded, .notSupported, .authenticationRequired: return true
        default: return false
        }
    }

    private func isPermanentReplayError(_ error: GmailAPIError) -> Bool {
        switch error {
        case .reauthenticationRequired, .domainPolicy, .httpFailure(statusCode: 403), .httpFailure(statusCode: 404):
            return true
        default:
            return false
        }
    }

    private func recordConflict(_ mutation: PendingMutation, message: String) async {
        let conflict = MutationConflict(mutation: mutation, reason: .rejectedByServer, message: message)
        try? await offlineMutationConflictStore?.append([conflict])
        lock.withLock { replayConflictCount += 1 }
    }

    private func reconcile(_ reconciler: GmailSyncReconciler) async throws {
        let before = try await store.messages(accountID: account.id)
        let state: GmailAccountState
        do {
            do {
                state = try await reconciler.sync()
            } catch GmailSyncError.fullSyncRequired {
                state = try await reconciler.fullSync()
            }
        } catch {
            recordSyncFailure(error)
            throw Self.providerNeutralError(error)
        }
        let after = try await store.messages(accountID: account.id)
        let labels = try await store.labels(accountID: account.id)
        lock.withLock {
            labelCatalog = labels
            profile = GmailProfile(emailAddress: state.emailAddress, historyID: state.historyID)
            lastSyncError = nil
            lastSuccessfulSyncAt = Date()
            isConnected = true
        }
        emitDiff(before: before, after: after)
    }

    private func recordSyncFailure(_ error: Error) {
        lock.withLock {
            lastSyncError = Self.providerNeutralError(error).localizedDescription
        }
    }

    private static func providerNeutralError(_ error: Error) -> Error {
        if let error = error as? GmailSyncError {
            if case .api(let apiError) = error {
                return providerNeutralError(apiError)
            }
            return error
        }
        guard let error = error as? GmailAPIError else { return error }
        switch error {
        case .reauthenticationRequired:
            return MailBackendError.authenticationRequired
        default:
            return error
        }
    }

    private func emitDiff(before: [GmailMessage], after: [GmailMessage]) {
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let added = new.keys.filter { old[$0] == nil }.sorted()
        let removed = old.keys.filter { new[$0] == nil }.sorted()
        let updated = new.keys.filter { id in
            guard let previous = old[id], let current = new[id] else { return false }
            return previous != current
        }.sorted()
        let boundedAdded = Array(added.prefix(1000))
        let boundedRemoved = Array(removed.prefix(1000))
        let boundedUpdated = Array(updated.prefix(1000))
        for messageID in boundedAdded {
            emit(.messagesAdded(
                folderID: Self.primaryFolderID(for: new[messageID]!, labels: labelCatalog),
                messageIDs: [messageID]
            ))
        }
        for messageID in boundedRemoved {
            emit(.messagesRemoved(
                folderID: Self.primaryFolderID(for: old[messageID]!, labels: labelCatalog),
                messageIDs: [messageID]
            ))
        }
        for messageID in boundedUpdated {
            emit(.messagesUpdated(
                folderID: Self.primaryFolderID(for: new[messageID]!, labels: labelCatalog),
                messageIDs: [messageID]
            ))
        }
    }

    private func emit(_ event: MailEvent) {
        let continuations = lock.withLock { Array(subscribers.values) }
        continuations.forEach { $0.yield(event) }
    }

    private func unsupported() -> MailBackendError { .notSupported(capabilities) }

    private func validateSource(_ sourceID: MailSourceID?) throws {
        guard sourceID == nil || sourceID?.accountID == account.id else {
            throw MailBackendError.notFound(id: sourceID?.accountID ?? account.id)
        }
    }

    private func mutationClient() throws -> any GmailAPIClientProtocol {
        guard let client else { throw unsupported() }
        try requireConnected()
        return client
    }

    private func canonicalMessage(_ messageID: String) async throws -> GmailMessage {
        guard let message = try await store.message(accountID: account.id, messageID: messageID) else {
            throw MailBackendError.notFound(id: messageID)
        }
        return message
    }

    private func applyLabelMutation(messageIDs: [String], add: [String], remove: [String]) async throws {
        let client = try mutationClient()
        guard !messageIDs.isEmpty else { return }
        for chunk in messageIDs.chunked(maxCount: 1000) {
            do {
                try await client.batchModifyMessageLabels(
                    messageIDs: chunk,
                    addLabelIDs: add,
                    removeLabelIDs: remove
                )
            } catch GmailAPIError.invalidRequest {
                for messageID in chunk {
                    _ = try await client.modifyMessageLabels(
                        id: messageID,
                        addLabelIDs: add,
                        removeLabelIDs: remove
                    )
                }
            }
            for messageID in chunk {
                let current = try await canonicalMessage(messageID)
                let labels = Set(current.labelIDs)
                    .subtracting(remove)
                    .union(add)
                try await store.apply(GmailStoreDelta(
                    accountID: account.id,
                    upsertedMessages: [Self.message(current, labels: labels.sorted())]
                ))
            }
        }
    }

    private func refreshStoredMessages(_ messageIDs: [String]) async throws {
        guard let client else { throw unsupported() }
        for messageID in messageIDs {
            let message = try await client.getMessage(
                id: messageID,
                format: .metadata,
                metadataHeaders: GmailAPIClient.requiredMetadataHeaders
            )
            try await store.apply(GmailStoreDelta(accountID: account.id, upsertedMessages: [message]))
        }
    }

    private func resolveLabelID(_ value: String) throws -> String {
        let labels = lock.withLock { labelCatalog }
        guard let label = labels.first(where: {
            $0.id == value
                || $0.name == value
                || $0.name.split(separator: "/").last.map(String.init) == value
        }) else {
            throw MailBackendError.notFound(id: value)
        }
        return label.id
    }

    private func label(id: String) throws -> GmailLabel {
        guard let label = lock.withLock({ labelCatalog.first(where: { $0.id == id }) }) else {
            throw MailBackendError.notFound(id: id)
        }
        return label
    }

    private func updateLabelCatalog(_ label: GmailLabel) {
        lock.withLock {
            if let index = labelCatalog.firstIndex(where: { $0.id == label.id }) {
                labelCatalog[index] = label
            } else {
                labelCatalog.append(label)
            }
        }
    }

    private func message(_ messageID: String) async throws -> GmailMessage {
        if let cached = try await store.message(accountID: account.id, messageID: messageID) {
            return cached
        }
        let fetched = try await transport.getMessage(messageID: messageID, format: .full)
        try Task.checkCancellation()
        if try await store.accountState(accountID: account.id) != nil {
            try await store.apply(GmailStoreDelta(accountID: account.id, upsertedMessages: [fetched]))
        }
        return fetched
    }

    private func downloadAttachment(messageID: String, attachmentID: String, cacheID: String) async throws -> Data {
        if let cached = try await readCache?.cachedAttachment(accountID: account.id, attachmentID: cacheID) {
            return cached
        }
        if let message = try await store.message(accountID: account.id, messageID: messageID),
           let part = Self.part(in: message.payload, id: attachmentID),
           let encoded = part.body?.data,
           let data = Self.decodeBase64URL(encoded) {
            try await readCache?.storeAttachment(data, accountID: account.id, attachmentID: cacheID)
            return data
        }
        let attachment = try await transport.getAttachment(messageID: messageID, attachmentID: attachmentID)
        guard let encoded = attachment.data, let data = Self.decodeBase64URL(encoded) else {
            throw GmailAPIError.malformedResponse
        }
        try await readCache?.storeAttachment(data, accountID: account.id, attachmentID: cacheID)
        return data
    }

    private static func folders(from labels: [GmailLabel]) -> [Folder] {
        labels.map { label in
            Folder(
                id: label.id,
                name: label.name,
                role: role(for: label),
                parentID: parentID(for: label, among: labels),
                unreadCount: label.messagesUnread ?? 0,
                totalCount: label.messagesTotal ?? 0
            )
        }
    }

    public func serverSearchSyntax(for sourceID: MailSourceID) async throws -> ServerSearchSyntaxDescription? {
        try validateSource(sourceID)
        return ServerSearchSyntaxDescription(
            identifier: "gmail-q",
            displayName: "Gmail search",
            summary: "Search Gmail with operators such as from:, label:, has:attachment, and is:unread.",
            examples: [
                ServerSearchSyntaxExample(query: "from:alice@example.com", explanation: "Messages from a sender."),
                ServerSearchSyntaxExample(query: "has:attachment", explanation: "Messages with attachments."),
                ServerSearchSyntaxExample(query: "is:unread", explanation: "Unread messages.")
            ],
            documentationURL: URL(string: "https://support.google.com/mail/answer/7190")
        )
    }

    private static func providerLabel(from label: GmailLabel, labels: [GmailLabel]) -> ProviderLabel {
        let knownSystemIDs: Set<String> = [
            "INBOX", "SPAM", "TRASH", "SENT", "DRAFT", "STARRED", "IMPORTANT", "ALL_MAIL", "SNOOZED", "UNREAD"
        ]
        let kind: ProviderLabelKind = label.type == "user" || !knownSystemIDs.contains(label.id) ? .user : .system
        let visibility = ProviderLabelVisibility(
            sidebar: providerListVisibility(label.labelListVisibility),
            messageList: providerMessageVisibility(label.messageListVisibility)
        )
        let color = label.color.map {
            ProviderLabelColor(foregroundHex: $0.textColor, backgroundHex: $0.backgroundColor)
        }
        let counts = ProviderLabelCounts(
            messagesTotal: label.messagesTotal,
            messagesUnread: label.messagesUnread,
            threadsTotal: label.threadsTotal,
            threadsUnread: label.threadsUnread
        )
        let parentID: String? = label.name.lastIndex(of: "/").flatMap { slash in
            let parentName = String(label.name[..<slash])
            return labels.first { $0.name == parentName }?.id
        }
        return ProviderLabel(
            id: label.id,
            name: label.name,
            parentID: parentID,
            kind: kind,
            visibility: visibility,
            color: color,
            counts: counts,
            allowedOperations: kind == .user
                ? [.rename, .delete, .setVisibility, .setColor, .applyToMessages, .removeFromMessages]
                : nil
        )
    }

    private static func providerListVisibility(_ value: String?) -> ProviderLabelListVisibility {
        switch value {
        case "labelHide": return .hidden
        case "labelShowIfUnread": return .shownIfUnread
        default: return .shown
        }
    }

    private static func providerMessageVisibility(_ value: String?) -> ProviderLabelMessageVisibility {
        value == "hide" ? .hidden : .shown
    }

    private static func gmailListVisibility(_ visibility: ProviderLabelVisibility) -> String {
        switch visibility.sidebar {
        case .shown: return "labelShow"
        case .shownIfUnread: return "labelShowIfUnread"
        case .hidden: return "labelHide"
        }
    }

    private static func gmailMessageVisibility(_ visibility: ProviderLabelVisibility) -> String {
        visibility.messageList == .hidden ? "hide" : "show"
    }

    private static func fullLabelName(name: String, parentID: String?, labels: [GmailLabel]) -> String {
        guard let parentID, let parent = labels.first(where: { $0.id == parentID }), !parent.name.isEmpty else {
            return name
        }
        return "\(parent.name)/\(name)"
    }

    private static func parentID(for label: GmailLabel, labels: [GmailLabel]) -> String? {
        guard let slash = label.name.lastIndex(of: "/") else { return nil }
        let parentName = String(label.name[..<slash])
        return labels.first { $0.name == parentName }?.id
    }

    private static func message(_ message: GmailMessage, labels: [String]) -> GmailMessage {
        GmailMessage(
            id: message.id,
            threadID: message.threadID,
            labelIDs: labels,
            snippet: message.snippet,
            historyID: message.historyID,
            internalDate: message.internalDate,
            sizeEstimate: message.sizeEstimate,
            payload: message.payload,
            raw: message.raw
        )
    }

    private static func role(for label: GmailLabel) -> FolderRole {
        switch label.id.uppercased() {
        case "INBOX": return .inbox
        case "SENT": return .sent
        case "DRAFT": return .drafts
        case "TRASH": return .trash
        case "SPAM": return .spam
        case "ALL_MAIL": return .allMail
        case "STARRED": return .starred
        case "SNOOZED": return .snoozed
        default: return .custom
        }
    }

    private static func parentID(for label: GmailLabel, among labels: [GmailLabel]) -> String? {
        guard let slash = label.name.lastIndex(of: "/") else { return nil }
        let parentName = String(label.name[..<slash])
        return labels.first { $0.name == parentName }?.id
    }

    private static func primaryFolderID(for message: GmailMessage, labels: [GmailLabel]) -> String {
        message.labelIDs.first { id in labels.contains { $0.id == id } } ?? "ALL_MAIL"
    }

    private static func header(from message: GmailMessage, folderID: String, labels: [GmailLabel]) -> MessageHeader {
        let headers = Self.headerMap(message.payload?.headers ?? [])
        let from = correspondents(headers["from"] ?? "").first ?? Correspondent(email: "unknown@example.invalid")
        let date = parseDate(headers["date"], internalDate: message.internalDate)
        let labelNames = message.labelIDs.map { id in
            switch id.uppercased() {
            case "INBOX": return "\\Inbox"
            case "SENT": return "\\Sent"
            case "DRAFT": return "\\Draft"
            case "TRASH": return "\\Trash"
            case "SPAM": return "\\Junk"
            case "STARRED": return "\\Starred"
            case "IMPORTANT": return "\\Important"
            default: return labels.first { $0.id == id }?.name ?? id
            }
        }
        return MessageHeader(
            id: message.id,
            threadID: message.threadID ?? message.id,
            folderID: folderID,
            from: from,
            replyTo: correspondents(headers["reply-to"] ?? ""),
            to: correspondents(headers["to"] ?? ""),
            cc: correspondents(headers["cc"] ?? ""),
            bcc: correspondents(headers["bcc"] ?? ""),
            subject: headers["subject"] ?? "",
            snippet: message.snippet ?? "",
            date: date,
            isRead: !message.labelIDs.contains("UNREAD"),
            isFlagged: message.labelIDs.contains("STARRED"),
            isAnswered: message.labelIDs.contains("ANSWERED"),
            hasAttachments: hasAttachments(message.payload),
            messageID: headers["message-id"],
            inReplyTo: headers["in-reply-to"],
            labels: labelNames
        )
    }

    private static func body(from message: GmailMessage) -> MessageBody {
        guard let payload = message.payload else {
            return MessageBody(messageID: message.id)
        }
        var plain: String?
        var html: String?
        var attachments: [Attachment] = []
        collectParts(payload, messageID: message.id, plain: &plain, html: &html, attachments: &attachments)
        let headers = headerMap(payload.headers)
        return MessageBody(
            messageID: message.id,
            html: html,
            plainText: plain,
            attachments: attachments,
            readReceiptRequest: headers["disposition-notification-to"].map(ReadReceiptRequest.init),
            authenticationResults: headers["authentication-results"]
        )
    }

    private static func collectParts(
        _ part: GmailMessagePart,
        messageID: String,
        plain: inout String?,
        html: inout String?,
        attachments: inout [Attachment]
    ) {
        for child in part
            .parts {
            collectParts(child, messageID: messageID, plain: &plain, html: &html, attachments: &attachments)
        }
        let mimeType = part.mimeType?.lowercased() ?? ""
        if mimeType == "text/plain", let data = part.body?.data.flatMap(decodeBase64URL) {
            plain = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } else if mimeType == "text/html", let data = part.body?.data.flatMap(decodeBase64URL) {
            html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }
        if let filename = part.filename, !filename.isEmpty {
            let contentID = part.headers.first { $0.name.caseInsensitiveCompare("Content-ID") == .orderedSame }?.value
            let providerAttachmentID = part.body?.attachmentID ?? part.partID ?? filename
            attachments.append(Attachment(
                id: "gmail-attachment:\(messageID):\(part.partID ?? filename)",
                name: filename,
                mimeType: part.mimeType ?? "application/octet-stream",
                sizeBytes: part.body?.size ?? 0,
                isInline: contentID != nil,
                contentID: contentID?.trimmingCharacters(in: CharacterSet(charactersIn: "<>")),
                resource: "\(messageID)|\(providerAttachmentID)"
            ))
        }
    }

    private static func hasAttachments(_ part: GmailMessagePart?) -> Bool {
        guard let part else { return false }
        return (part.filename?.isEmpty == false) || part.parts.contains(where: hasAttachments)
    }

    private static func part(in root: GmailMessagePart?, id: String) -> GmailMessagePart? {
        guard let root else { return nil }
        if root.partID == id || root.body?.attachmentID == id { return root }
        for child in root.parts where Self.part(in: child, id: id) != nil {
            return Self.part(in: child, id: id)
        }
        return nil
    }

    private static func correspondents(_ value: String) -> [Correspondent] {
        value.split(separator: ",").compactMap { token in
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let start = trimmed.lastIndex(of: "<"), let end = trimmed.lastIndex(of: ">"), start < end {
                let email = String(trimmed[trimmed.index(after: start) ..< end]).trimmingCharacters(in: .whitespaces)
                let name = String(trimmed[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
                return Correspondent(name: name.isEmpty ? nil : name, email: email)
            }
            return Correspondent(email: trimmed)
        }
    }

    private static func parseDate(_ value: String?, internalDate: String?) -> Date {
        if let value {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            if let date = formatter.date(from: value) { return date }
        }
        if let internalDate, let milliseconds = Double(internalDate) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        return .distantPast
    }

    private static func headerMap(_ headers: [GmailMessageHeader]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, header in
            let key = header.name.lowercased()
            if result[key] == nil { result[key] = header.value }
        }
    }

    private static func gmailQuery(from query: SearchQuery) -> String {
        var terms = [String]()
        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { terms.append(query.text) }
        if let from = query.from, !from.isEmpty { terms.append("from:\(from)") }
        if let to = query.to, !to.isEmpty { terms.append("to:\(to)") }
        if let subject = query.subject, !subject.isEmpty { terms.append("subject:\(subject)") }
        if query.hasAttachments == true { terms.append("has:attachment") }
        if query.isUnread == true { terms.append("is:unread") }
        if query.isFlagged == true { terms.append("is:starred") }
        if let folderID = query.folderID { terms.append("label:\(folderID)") }
        if let range = query.dateRange {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            terms.append("after:\(formatter.string(from: range.lowerBound))")
            terms.append("before:\(formatter.string(from: range.upperBound))")
        }
        return terms.joined(separator: " ")
    }

    private struct SearchScope {
        let labelID: String?
        let query: String
        let includeSpamTrash: Bool
    }

    private static func searchScope(for query: SearchQuery, labels: [GmailLabel]) -> SearchScope {
        var terms = [String]()
        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { terms.append(query.text) }
        if let from = query.from, !from.isEmpty { terms.append("from:\(from)") }
        if let to = query.to, !to.isEmpty { terms.append("to:\(to)") }
        if let subject = query.subject, !subject.isEmpty { terms.append("subject:\(subject)") }
        if query.hasAttachments == true { terms.append("has:attachment") }
        if query.isUnread == true { terms.append("is:unread") }
        if query.isFlagged == true { terms.append("is:starred") }
        if let range = query.dateRange {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            terms.append("after:\(formatter.string(from: range.lowerBound))")
            terms.append("before:\(formatter.string(from: range.upperBound))")
        }

        var labelID: String?
        if let folderID = query.folderID,
           let label = labels.first(where: { $0.id == folderID || $0.name == folderID }) {
            switch label.id.uppercased() {
            case "INBOX": terms.append("in:inbox")
            case "SPAM": terms.append("in:spam")
            case "TRASH": terms.append("in:trash")
            case "ALL_MAIL": terms.append("in:anywhere")
            case "SENT": terms.append("in:sent")
            case "DRAFT": terms.append("in:drafts")
            case "STARRED": terms.append("is:starred")
            case "IMPORTANT": terms.append("is:important")
            default:
                let escaped = label.name.replacingOccurrences(of: "\\\"", with: "\\\\\"")
                terms.append("label:\"\(escaped)\"")
            }
        } else if let folderID = query.folderID, !folderID.isEmpty {
            labelID = folderID
        }
        let joined = terms.joined(separator: " ")
        let includeSpamTrash = joined
            .range(of: #"(?:^|\s)in:(?:anywhere|spam|trash)(?:\s|$)"#, options: .regularExpression) != nil
        return SearchScope(labelID: labelID, query: joined, includeSpamTrash: includeSpamTrash)
    }

    private static func hasBodyContent(_ body: MessageBody) -> Bool {
        body.plainText != nil || body.html != nil || !body.attachments.isEmpty
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: Swift.min(maxCount, distance(from: index, to: endIndex)))
            chunks.append(Array(self[index ..< end]))
            index = end
        }
        return chunks
    }
}

// Keeps provider-batch progress across explicit Undo retries.
private actor GmailMoveUndoProgress {
    private var restoredIDs: Set<String> = []
    private var isRestoring = false

    func restore(_ messageIDs: [String], operation: @Sendable (String) async throws -> Void) async throws {
        guard !isRestoring else { throw GmailAPIError.invalidRequest }
        isRestoring = true
        defer { isRestoring = false }
        for id in messageIDs where !restoredIDs.contains(id) {
            try Task.checkCancellation()
            try await operation(id)
            restoredIDs.insert(id)
        }
    }
}
