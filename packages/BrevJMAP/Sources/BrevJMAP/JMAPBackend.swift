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

/// Native RFC 8620 / RFC 8621 JMAP mail backend behind Brev's provider-neutral `MailBackend` contract.
///
/// Uses single-round-trip batched JMAP calls (`#resultRef`), state-token delta sync
/// (`Mailbox/changes`, `Email/changes`), RFC 8620 §7.3 `EventSource` SSE live updates,
/// and RFC 8620 §7.2 `PushSubscription/set` WebPush integration.
public final class JMAPBackend: MailBackend,
    MailboxBackgroundRefreshing,
    CachedMessageHeaderProviding,
    CachedMessageBodyProviding,
    CachedListUnsubscribeProviding,
    LocalDraftAttachmentProviding,
    SyncHealthReporting,
    @unchecked Sendable {
    private static let pageSize = 50
    private static let maxEventSourceBackoffSeconds: TimeInterval = 60

    private struct StagedAttachment: Sendable {
        let id: String
        let draftID: String
        let filename: String
        let mimeType: String
        let data: Data
        let contentID: String?
        var uploadedBlobID: String?
    }

    /// Account metadata bound to this backend instance.
    public let account: BrevAccount

    private let sessionURL: URL
    private let tokenProvider: any JMAPAccessTokenProvider
    private let transport: any JMAPHTTPTransport
    private let sessionClient: JMAPSessionClient
    private let client: JMAPClient
    private let now: @Sendable () -> Date
    private let eventSourceRetryDelay: @Sendable (Int) -> UInt64

    private let lock = NSLock()
    private var isConnected = false
    private var session: JMAPSession?
    private var primaryAccountID: String?
    private var mailboxState: String?
    private var emailState: String?
    private var mailboxesByID: [String: JMAPMailbox] = [:]
    private var identities: [JMAPIdentity] = []
    private var headersByFolderID: [String: [MessageHeader]] = [:]
    private var emailsByID: [String: JMAPEmail] = [:]
    private var bodiesByID: [String: MessageBody] = [:]
    private var rawSourceDataByID: [String: Data] = [:]
    private var freshDeliveryTimestamps: [String: Date] = [:]
    private var stagedAttachmentsByID: [String: StagedAttachment] = [:]
    private var stagedDraftsByRemoteID: [String: Draft] = [:]
    private var stagedDraftsByLocalID: [String: Draft] = [:]
    private var remoteDraftIDByLocalID: [String: String] = [:]
    private var subscribers: [UUID: AsyncStream<MailEvent>.Continuation] = [:]
    private var eventSourceTask: Task<Void, Never>?
    private var lastSuccessfulSyncAt: Date?
    private var lastSyncError: String?
    private var lastSyncRequiresReauth = false

    /// Creates a native JMAP backend for `account` using strict HTTPS `sessionURL`.
    ///
    /// - Parameters:
    ///   - account: Provider-neutral `BrevAccount` identity (`jmap:<email>`).
    ///   - sessionURL: Validated HTTPS discovery URL (`/.well-known/jmap` or explicit session URL).
    ///   - tokenProvider: Supplies the Bearer / API token from Keychain (`TokenStore`).
    ///   - transport: Injectable HTTP + EventSource transport (defaults to `URLSessionJMAPHTTPTransport.shared`).
    ///   - now: Clock used for sync timestamps and fresh-delivery watermarks.
    ///   - eventSourceRetryDelay: Backoff delay function (nanoseconds for 1-based failure attempt).
    public init(
        account: BrevAccount,
        sessionURL: URL,
        tokenProvider: any JMAPAccessTokenProvider,
        transport: any JMAPHTTPTransport = URLSessionJMAPHTTPTransport.shared,
        now: @escaping @Sendable () -> Date = { Date() },
        eventSourceRetryDelay: (@Sendable (Int) -> UInt64)? = nil
    ) {
        self.account = account
        self.sessionURL = sessionURL
        self.tokenProvider = tokenProvider
        self.transport = transport
        sessionClient = JMAPSessionClient(transport: transport)
        client = JMAPClient(transport: transport, tokenProvider: tokenProvider)
        self.now = now
        self.eventSourceRetryDelay = eventSourceRetryDelay ?? { attempt in
            let exponent = min(max(0, attempt - 1), 6)
            let seconds = min(Double(1 << exponent), JMAPBackend.maxEventSourceBackoffSeconds)
            return UInt64(seconds * 1_000_000_000)
        }
    }

    /// Last discovered JMAP session, if connected.
    public var currentSession: JMAPSession? {
        lock.withLock { session }
    }

    /// Current JMAP `Mailbox` state token, if known.
    public var currentMailboxState: String? {
        lock.withLock { mailboxState }
    }

    /// Current JMAP `Email` state token, if known.
    public var currentEmailState: String? {
        lock.withLock { emailState }
    }

    /// Advertised provider capabilities driven strictly by the discovered JMAP session.
    public var capabilities: BackendCapabilities {
        lock.withLock {
            guard isConnected, let session else { return [] }
            var caps: BackendCapabilities = [
                .providerAPI,
                .jmapMail,
                .serverSideSearch,
                .serverSideThreading,
                .historyDeltaSync,
                .folderCreate,
                .folderRename,
                .folderDelete,
                .folderFlush,
                .flagColors,
                .listUnsubscribeHeaders,
                .providerSyncHealth
            ]
            if let eventURL = session.eventSourceUrl, !eventURL.isEmpty {
                caps.insert(.idleSync)
            }
            if !identities.isEmpty {
                caps.insert(.aliases)
                if identities.contains(where: { !$0.htmlSignature.isEmpty || !$0.textSignature.isEmpty }) {
                    caps.insert(.serverSignatures)
                }
            }
            return caps
        }
    }

    /// Advertised extended capabilities driven strictly by JMAP primitives and identities.
    public var extendedCapabilities: BackendExtendedCapabilities {
        lock.withLock {
            var caps: BackendExtendedCapabilities = [
                .messageCopy,
                .rawMessageSource,
                .rawMessageBytes,
                .cachedMessageHeaders,
                .cachedConversations
            ]
            if isConnected, !identities.isEmpty {
                caps.insert(.serverAliases)
                if identities.contains(where: { !$0.htmlSignature.isEmpty || !$0.textSignature.isEmpty }) {
                    caps.insert(.serverSignatures)
                }
                if identities.count > 1 {
                    caps.insert(.sendAs)
                }
            }
            return caps
        }
    }

    /// Exposes capability-gated optional provider services without concrete backend type checks.
    public func extensionService<Service>(_ type: Service.Type) -> Service? {
        if type == MailboxBackgroundRefreshing.self { return self as? Service }
        if type == CachedMessageHeaderProviding.self { return self as? Service }
        if type == CachedMessageBodyProviding.self { return self as? Service }
        if type == CachedListUnsubscribeProviding.self { return self as? Service }
        if type == LocalDraftAttachmentProviding.self { return self as? Service }
        if type == SyncHealthReporting.self { return self as? Service }
        return nil
    }

    // MARK: - Lifecycle

    /// Discovers the JMAP session, fetches initial mailboxes and identities, and marks the backend connected.
    public func connect() async throws {
        do {
            let token = try await tokenProvider.bearerToken()
            let discovered = try await sessionClient.discoverSession(from: sessionURL, bearerToken: token)
            guard let accountId = discovered.primaryMailAccountID else {
                throw JMAPError.missingPrimaryMailAccount
            }
            let initial = try await client.fetchInitialState(session: discovered, accountId: accountId)
            let timestamp = now()

            lock.withLock {
                self.session = discovered
                primaryAccountID = accountId
                mailboxState = initial.mailboxes.state
                mailboxesByID = Dictionary(uniqueKeysWithValues: initial.mailboxes.list.map { ($0.id, $0) })
                identities = initial.identities?.list ?? []
                isConnected = true
                lastSuccessfulSyncAt = timestamp
                lastSyncError = nil
                lastSyncRequiresReauth = false
            }

            broadcast(.accountConnected(accountID: account.id))
            startEventSourceIfNeeded()
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        } catch let error as MailBackendError {
            throw error
        } catch {
            throw MailBackendError.network(underlying: JMAPError.networkFailure.localizedDescription)
        }
    }

    /// Cancels active EventSource streams and marks the backend disconnected.
    public func disconnect() async {
        let taskToCancel: Task<Void, Never>? = lock.withLock {
            isConnected = false
            let existing = eventSourceTask
            eventSourceTask = nil
            return existing
        }
        taskToCancel?.cancel()
        broadcast(.accountDisconnected(accountID: account.id))
    }

    // MARK: - Folders

    /// Returns all JMAP mailboxes mapped to `Folder`, sorted by role priority and sort order.
    public func folders() async throws -> [Folder] {
        let (connected, cached) = lock.withLock { (isConnected, Array(mailboxesByID.values)) }
        guard connected else {
            throw MailBackendError.notConnected
        }
        if !cached.isEmpty {
            return Self.sortedFolders(from: cached)
        }
        let (session, accountId) = try requireConnectedSession()
        do {
            let response = try await client.getMailboxes(session: session, accountId: accountId)
            lock.withLock {
                mailboxState = response.state
                mailboxesByID = Dictionary(uniqueKeysWithValues: response.list.map { ($0.id, $0) })
            }
            return Self.sortedFolders(from: response.list)
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Refreshes mailbox metadata and applies incremental delta sync (falling back cleanly to full refresh).
    public func refresh(folder: Folder) async throws {
        _ = try requireConnectedSession()
        do {
            let didFullRefresh = try await performDeltaSync(fallbackFolder: folder)
            if !didFullRefresh, lock.withLock({ headersByFolderID[folder.id] == nil }) {
                _ = try await fetchMessagesPage(in: folder, pageToken: nil)
            }
            broadcast(.folderRefreshed(folderID: folder.id))
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Creates a new custom JMAP mailbox (`Mailbox/set`).
    public func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder {
        let (session, accountId) = try requireConnectedSession()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MailBackendError.backendSpecific(message: JMAPError.invalidConfiguration.localizedDescription)
        }
        var createObject: [String: JMAPJSONValue] = [
            "name": .string(trimmedName)
        ]
        if let parentID, !parentID.isEmpty {
            createObject["parentId"] = .string(parentID)
        }
        do {
            let result = try await client.setMailboxes(
                session: session,
                accountId: accountId,
                create: ["new-mailbox": createObject]
            )
            guard let createdID = result.created?["new-mailbox"]?["id"]?.stringValue else {
                throw JMAPError.invalidResponse
            }
            let mailbox = JMAPMailbox(
                id: createdID,
                name: trimmedName,
                parentId: parentID
            )
            lock.withLock {
                mailboxesByID[createdID] = mailbox
            }
            let folder = mailbox.toFolder()
            broadcast(.folderRefreshed(folderID: folder.id))
            return folder
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Renames an existing JMAP mailbox (`Mailbox/set`).
    public func renameFolder(id: Folder.ID, name: String) async throws -> Folder {
        let (session, accountId) = try requireConnectedSession()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MailBackendError.backendSpecific(message: JMAPError.invalidConfiguration.localizedDescription)
        }
        do {
            _ = try await client.setMailboxes(
                session: session,
                accountId: accountId,
                update: [id: ["name": .string(trimmedName)]]
            )
            let updatedMailbox: JMAPMailbox = lock.withLock {
                if let existing = mailboxesByID[id] {
                    let renamed = JMAPMailbox(
                        id: existing.id,
                        name: trimmedName,
                        parentId: existing.parentId,
                        role: existing.role,
                        sortOrder: existing.sortOrder,
                        totalEmails: existing.totalEmails,
                        unreadEmails: existing.unreadEmails,
                        totalThreads: existing.totalThreads,
                        unreadThreads: existing.unreadThreads,
                        isSubscribed: existing.isSubscribed
                    )
                    mailboxesByID[id] = renamed
                    return renamed
                }
                let fallback = JMAPMailbox(id: id, name: trimmedName)
                mailboxesByID[id] = fallback
                return fallback
            }
            let folder = updatedMailbox.toFolder()
            broadcast(.folderRefreshed(folderID: folder.id))
            return folder
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Deletes a JMAP mailbox (`Mailbox/set`).
    public func deleteFolder(id: Folder.ID) async throws {
        let (session, accountId) = try requireConnectedSession()
        do {
            _ = try await client.setMailboxes(
                session: session,
                accountId: accountId,
                destroy: [id]
            )
            lock.withLock {
                mailboxesByID.removeValue(forKey: id)
                headersByFolderID.removeValue(forKey: id)
            }
            broadcast(.folderRefreshed(folderID: id))
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Purges all emails from a mailbox (such as Trash or Junk) via `Email/query` + `Email/set` `destroy`.
    ///
    /// Respects server-advertised `maxObjectsInSet`, loops from position 0 until the folder is genuinely
    /// empty (even when the server caps query pages), verifies deletion progress, and reconciles only
    /// IDs confirmed in `destroyed`.
    public func flushFolder(id: Folder.ID) async throws {
        let (session, accountId) = try requireConnectedSession()
        let setBatchLimit = max(1, min(500, session.maxObjectsInSet ?? 500))
        do {
            var allDestroyed: [String] = []
            while true {
                try Task.checkCancellation()
                let query = try await client.queryEmailIDs(
                    session: session,
                    accountId: accountId,
                    filter: ["inMailbox": .string(id)],
                    position: 0,
                    limit: setBatchLimit
                )
                guard !query.ids.isEmpty else { break }

                var destroyedInRound: [String] = []
                var chunkStart = 0
                while chunkStart < query.ids.count {
                    let chunkEnd = min(chunkStart + setBatchLimit, query.ids.count)
                    let chunk = Array(query.ids[chunkStart ..< chunkEnd])
                    chunkStart = chunkEnd

                    let setResult = try await client.setEmails(
                        session: session,
                        accountId: accountId,
                        destroy: chunk,
                        validateResult: false
                    )
                    let confirmed = setResult.destroyed ?? []
                    if !confirmed.isEmpty {
                        let confirmedSet = Set(confirmed)
                        lock.withLock {
                            for removedID in confirmed {
                                emailsByID.removeValue(forKey: removedID)
                                bodiesByID.removeValue(forKey: removedID)
                                rawSourceDataByID.removeValue(forKey: removedID)
                            }
                            if let existing = headersByFolderID[id] {
                                headersByFolderID[id] = existing.filter { !confirmedSet.contains($0.id) }
                            }
                        }
                        destroyedInRound.append(contentsOf: confirmed)
                        allDestroyed.append(contentsOf: confirmed)
                    }
                    if let setError = JMAPClient.firstSetError(in: setResult) {
                        if !allDestroyed.isEmpty {
                            broadcast(.messagesRemoved(folderID: id, messageIDs: allDestroyed))
                            broadcast(.folderRefreshed(folderID: id))
                        }
                        throw setError
                    }
                    guard !confirmed.isEmpty else {
                        throw JMAPError.methodError(
                            type: "serverFail",
                            description: "Email/set destroy made no progress"
                        )
                    }
                }
                guard !destroyedInRound.isEmpty else {
                    throw JMAPError.methodError(
                        type: "serverFail",
                        description: "Email/set destroy made no progress"
                    )
                }
            }
            lock.withLock {
                headersByFolderID[id] = []
            }
            if !allDestroyed.isEmpty {
                broadcast(.messagesRemoved(folderID: id, messageIDs: allDestroyed))
            }
            broadcast(.folderRefreshed(folderID: id))
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    // MARK: - Messages & Bodies

    /// Fetches a page of headers in `folder` via single-round-trip batched `Email/query` + `Email/get`.
    public func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try await fetchMessagesPage(in: folder, pageToken: pageToken)
    }

    /// Enumerates a page of headers in `folder` without altering active live-watch state.
    public func enumerateMessages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try await fetchMessagesPage(in: folder, pageToken: pageToken)
    }

    /// Fetches full body text, HTML, inline `cid:` parts, downloadable attachments, and security/unsubscribe headers.
    public func body(for messageID: String) async throws -> MessageBody {
        let (session, accountId) = try requireConnectedSession()
        do {
            let response = try await client.getEmails(
                session: session,
                accountId: accountId,
                ids: [messageID],
                properties: JMAPClient.bodyProperties,
                fetchTextBodyValues: true,
                fetchHTMLBodyValues: true
            )
            guard let email = response.list.first else {
                throw JMAPError.notFound(id: messageID)
            }
            let mapped = email.toMessageBody()
            lock.withLock {
                // Do not advance the reconciled emailState cursor on single-message body fetches.
                emailsByID[messageID] = email
                bodiesByID[messageID] = mapped
            }
            return mapped
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Returns the raw RFC 5322 message source as UTF-8 text (cache-first, then `downloadUrl` blob download).
    public func rawSource(for messageID: String) async throws -> String {
        let data = try await rawMessageData(for: messageID)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Returns original RFC 5322 message bytes via RFC 8620 §6.2 `downloadUrl` blob download.
    public func rawMessageData(for messageID: String) async throws -> Data {
        if let cached = lock.withLock({ rawSourceDataByID[messageID] }) {
            return cached
        }
        let (session, accountId) = try requireConnectedSession()
        do {
            let blobID: String
            if let existingBlob = lock.withLock({ emailsByID[messageID]?.blobId }), !existingBlob.isEmpty {
                blobID = existingBlob
            } else {
                let response = try await client.getEmails(
                    session: session,
                    accountId: accountId,
                    ids: [messageID],
                    properties: ["id", "blobId"]
                )
                guard let fetched = response.list.first?.blobId, !fetched.isEmpty else {
                    throw JMAPError.notFound(id: messageID)
                }
                blobID = fetched
            }
            let bytes = try await client.downloadBlob(
                session: session,
                accountId: accountId,
                blobId: blobID,
                name: "\(messageID).eml",
                mimeType: "message/rfc822"
            )
            lock.withLock {
                rawSourceDataByID[messageID] = bytes
            }
            return bytes
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Downloads attachment bytes via RFC 8620 §6.2 `downloadUrl` template expansion.
    public func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        let (session, accountId) = try requireConnectedSession()
        guard let blobId = attachment.resource, !blobId.isEmpty else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        do {
            return try await client.downloadBlob(
                session: session,
                accountId: accountId,
                blobId: blobId,
                name: attachment.name,
                mimeType: attachment.mimeType
            )
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    // MARK: - Message Mutations

    /// Marks messages read (`$seen: true`) or unread (`$seen: null`) via `Email/set`.
    public func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        let patchValue: JMAPJSONValue = isRead ? .bool(true) : .null
        let updates = Dictionary(uniqueKeysWithValues: messageIDs.map { ($0, ["keywords/$seen": patchValue]) })
        do {
            _ = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs)) { header in
                header.isRead = isRead
            }
            for folderID in affectedFolders {
                broadcast(.messagesUpdated(folderID: folderID, messageIDs: messageIDs))
            }
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Sets or clears `$flagged` (and clears Apple flag-color bits when unflagging) via `Email/set`.
    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        var patch: [String: JMAPJSONValue] = [
            "keywords/$flagged": isFlagged ? .bool(true) : .null
        ]
        if !isFlagged {
            for bit in ["$MailFlagBit0", "$MailFlagBit1", "$MailFlagBit2"] {
                patch["keywords/\(bit)"] = .null
            }
        }
        let updates = Dictionary(uniqueKeysWithValues: messageIDs.map { ($0, patch) })
        do {
            _ = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs)) { header in
                header.isFlagged = isFlagged
                if !isFlagged { header.flagColor = nil }
            }
            for folderID in affectedFolders {
                broadcast(.messagesUpdated(folderID: folderID, messageIDs: messageIDs))
            }
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Sets or clears an Apple-compatible flag color using `$flagged` + `$MailFlagBit0..2` keywords via `Email/set`.
    public func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        let activeBits = color.map { AppleFlagKeyword.keywords(for: $0) } ?? []
        var patch: [String: JMAPJSONValue] = [:]
        if color != nil {
            patch["keywords/$flagged"] = .bool(true)
        }
        for bit in ["$MailFlagBit0", "$MailFlagBit1", "$MailFlagBit2"] {
            patch["keywords/\(bit)"] = activeBits.contains(bit) ? .bool(true) : .null
        }
        let updates = Dictionary(uniqueKeysWithValues: messageIDs.map { ($0, patch) })
        do {
            _ = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs)) { header in
                if color != nil { header.isFlagged = true }
                header.flagColor = color
            }
            for folderID in affectedFolders {
                broadcast(.messagesUpdated(folderID: folderID, messageIDs: messageIDs))
            }
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Moves messages to `folder` by replacing their `mailboxIds` map via `Email/set`.
    public func move(messageIDs: [String], to folder: Folder) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        let patch: [String: JMAPJSONValue] = [
            "mailboxIds": .object([folder.id: .bool(true)])
        ]
        let updates = Dictionary(uniqueKeysWithValues: messageIDs.map { ($0, patch) })
        do {
            _ = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let idSet = Set(messageIDs)
            var removedFromFolders: [String: [String]] = [:]
            var movedHeaders: [MessageHeader] = []
            lock.withLock {
                for (folderID, list) in headersByFolderID where folderID != folder.id {
                    let removed = list.filter { idSet.contains($0.id) }
                    if !removed.isEmpty {
                        removedFromFolders[folderID] = removed.map(\.id)
                        movedHeaders.append(contentsOf: removed.map { $0.withIdentity($0.id, folderID: folder.id) })
                        headersByFolderID[folderID] = list.filter { !idSet.contains($0.id) }
                    }
                }
                if !movedHeaders.isEmpty {
                    var destination = headersByFolderID[folder.id] ?? []
                    let existingIDs = Set(destination.map(\.id))
                    let uniqueAdded = movedHeaders.filter { !existingIDs.contains($0.id) }
                    destination.insert(contentsOf: uniqueAdded, at: 0)
                    headersByFolderID[folder.id] = destination
                }
            }
            for (sourceFolderID, removedIDs) in removedFromFolders {
                broadcast(.messagesRemoved(folderID: sourceFolderID, messageIDs: removedIDs))
            }
            broadcast(.messagesAdded(folderID: folder.id, messageIDs: messageIDs))
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Copies messages into `folder` while keeping their existing mailbox memberships via `Email/set` patch.
    public func copy(messageIDs: [String], to folder: Folder) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        let patch: [String: JMAPJSONValue] = [
            "mailboxIds/\(folder.id)": .bool(true)
        ]
        let updates = Dictionary(uniqueKeysWithValues: messageIDs.map { ($0, patch) })
        do {
            _ = try await client.setEmails(session: session, accountId: accountId, update: updates)
            broadcast(.messagesAdded(folderID: folder.id, messageIDs: messageIDs))
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Moves messages to the Trash mailbox, or permanently destroys them if already in Trash (or no Trash exists).
    public func delete(messageIDs: [String]) async throws {
        guard !messageIDs.isEmpty else { return }
        let (session, accountId) = try requireConnectedSession()
        let trashMailbox = lock.withLock {
            mailboxesByID.values.first(where: { $0.folderRole == .trash })
        }
        let allInTrash: Bool = if let trashMailbox {
            lock.withLock {
                let trashIDs = Set((headersByFolderID[trashMailbox.id] ?? []).map(\.id))
                return messageIDs.allSatisfy { id in
                    if trashIDs.contains(id) { return true }
                    if let email = emailsByID[id] {
                        return email.mailboxIds[trashMailbox.id] == true && email.mailboxIds.count == 1
                    }
                    return false
                }
            }
        } else {
            true
        }

        if let trashMailbox, !allInTrash {
            try await move(messageIDs: messageIDs, to: trashMailbox.toFolder())
            return
        }

        do {
            _ = try await client.setEmails(
                session: session,
                accountId: accountId,
                destroy: messageIDs
            )
            let idSet = Set(messageIDs)
            var removedFromFolders: [String: [String]] = [:]
            lock.withLock {
                for id in messageIDs {
                    emailsByID.removeValue(forKey: id)
                    bodiesByID.removeValue(forKey: id)
                    rawSourceDataByID.removeValue(forKey: id)
                }
                for (folderID, list) in headersByFolderID {
                    let removed = list.filter { idSet.contains($0.id) }.map(\.id)
                    if !removed.isEmpty {
                        removedFromFolders[folderID] = removed
                        headersByFolderID[folderID] = list.filter { !idSet.contains($0.id) }
                    }
                }
            }
            for (folderID, removedIDs) in removedFromFolders {
                broadcast(.messagesRemoved(folderID: folderID, messageIDs: removedIDs))
            }
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    // MARK: - Drafts & Outbound Send

    /// Stages an attachment for `draftID` (uploaded via `Blob/upload` when saving or sending).
    public func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        let attachmentID = "jmap-att-\(UUID().uuidString)"
        let staged = StagedAttachment(
            id: attachmentID,
            draftID: draftID,
            filename: filename,
            mimeType: mimeType,
            data: data,
            contentID: nil,
            uploadedBlobID: nil
        )
        lock.withLock {
            stagedAttachmentsByID[attachmentID] = staged
        }
        return attachmentID
    }

    /// Stages an inline `cid:` image for `draftID` (uploaded via `Blob/upload` when saving or sending).
    public func stageInlineAttachment(
        draftID: String,
        contentID: String,
        filename: String,
        mimeType: String,
        data: Data
    ) async throws -> String {
        let attachmentID = "jmap-cid-\(UUID().uuidString)"
        let staged = StagedAttachment(
            id: attachmentID,
            draftID: draftID,
            filename: filename,
            mimeType: mimeType,
            data: data,
            contentID: contentID,
            uploadedBlobID: nil
        )
        lock.withLock {
            stagedAttachmentsByID[attachmentID] = staged
        }
        return attachmentID
    }

    /// Saves or replaces a draft in the Drafts mailbox via `Email/set` (uploading any attachments via `Blob/upload`).
    public func save(draft: Draft) async throws -> Draft {
        let (session, accountId) = try requireConnectedSession()
        guard let draftsMailbox = lock.withLock({ mailboxesByID.values.first(where: { $0.folderRole == .drafts }) }) else {
            throw JMAPError.missingDraftsMailbox.asMailBackendError()
        }
        do {
            let uploadedAttachments = try await uploadStagedAttachments(
                for: draft,
                session: session,
                accountId: accountId
            )
            let fromIdentity = try await resolveIdentity(for: draft, session: session, accountId: accountId)
            let emailObject = buildEmailCreateObject(
                draft: draft,
                mailboxID: draftsMailbox.id,
                fromAddress: JMAPEmailAddress(
                    name: fromIdentity?.name.isEmpty == false ? fromIdentity?.name : account.displayName,
                    email: fromIdentity?.email ?? account.emailAddress
                ),
                isDraft: true,
                attachments: uploadedAttachments
            )
            // Create the new draft version FIRST so a rejected edit never erases the prior saved draft.
            let setResult = try await client.setEmails(
                session: session,
                accountId: accountId,
                create: ["draft": emailObject]
            )
            guard let createdMeta = setResult.created?["draft"],
                  let createdID = createdMeta["id"]?.stringValue
            else {
                throw JMAPError.invalidResponse
            }
            var updatedDraft = draft
            updatedDraft.remoteID = createdID
            if let threadID = createdMeta["threadId"]?.stringValue {
                updatedDraft.threadID = threadID
            }
            lock.withLock {
                if let oldRemote = draft.remoteID, oldRemote != createdID {
                    stagedDraftsByRemoteID.removeValue(forKey: oldRemote)
                }
                stagedDraftsByRemoteID[createdID] = updatedDraft
                stagedDraftsByLocalID[updatedDraft.id] = updatedDraft
                remoteDraftIDByLocalID[updatedDraft.id] = createdID
            }
            // Destroy the superseded remote draft separately; cleanup failure must not lose the new remoteID.
            if let existingRemoteID = draft.remoteID, !existingRemoteID.isEmpty, existingRemoteID != createdID {
                _ = try? await client.setEmails(
                    session: session,
                    accountId: accountId,
                    destroy: [existingRemoteID]
                )
            }
            broadcast(.folderRefreshed(folderID: draftsMailbox.id))
            return updatedDraft
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Returns a staged copy of a draft (reconstructing and locally staging remote JMAP drafts after restart).
    public func draft(for messageID: String) async throws -> Draft? {
        if let existing = lock.withLock({ stagedDraftsByRemoteID[messageID] ?? stagedDraftsByLocalID[messageID] }) {
            return existing
        }
        let connectedSession: (JMAPSession, String)? = lock.withLock {
            guard isConnected, let session, let primaryAccountID else { return nil }
            return (session, primaryAccountID)
        }
        guard let (session, accountId) = connectedSession else {
            return nil
        }

        do {
            let response = try await client.getEmails(
                session: session,
                accountId: accountId,
                ids: [messageID],
                properties: JMAPClient.draftProperties,
                fetchTextBodyValues: true,
                fetchHTMLBodyValues: true
            )
            guard let email = response.list.first else {
                return nil
            }
            let draftsMailboxIDs = lock.withLock {
                Set(mailboxesByID.values.filter { $0.folderRole == .drafts }.map(\.id))
            }
            let isDraft = email.keywords["$draft"] == true
                || email.mailboxIds.contains { $0.value && draftsMailboxIDs.contains($0.key) }
            guard isDraft else {
                return nil
            }

            let mappedBody = email.toMessageBody()
            let htmlBody: String = if let html = mappedBody.html {
                html
            } else {
                Self.escapedHTMLFromPlainText(mappedBody.plainText ?? "")
            }
            let referencedCIDs = Self.referencedContentIDs(inHTML: htmlBody)
            let draftLocalID = UUID().uuidString
            var stagedAttachments: [StagedAttachment] = []
            for attachment in mappedBody.attachments {
                guard let blobId = attachment.resource, !blobId.isEmpty else {
                    throw JMAPError.invalidDownloadURL
                }
                let bytes = try await client.downloadBlob(
                    session: session,
                    accountId: accountId,
                    blobId: blobId,
                    name: attachment.name,
                    mimeType: attachment.mimeType
                )
                // Only stage a part as inline when the editable HTML actually references its
                // normalized Content-ID; unreferenced attachment CIDs stay regular attachments.
                let inlineCID: String? = if let cid = attachment.contentID,
                                            !cid.isEmpty,
                                            referencedCIDs.contains(Self.normalizedContentID(cid)) {
                    cid
                } else {
                    nil
                }
                let stagedID = inlineCID != nil
                    ? "jmap-cid-\(UUID().uuidString)"
                    : "jmap-att-\(UUID().uuidString)"
                stagedAttachments.append(
                    StagedAttachment(
                        id: stagedID,
                        draftID: draftLocalID,
                        filename: attachment.name,
                        mimeType: attachment.mimeType,
                        data: bytes,
                        contentID: inlineCID,
                        uploadedBlobID: blobId
                    )
                )
            }

            let matchedIdentityID = try await resolveIdentityID(
                forFromAddress: email.from?.first,
                session: session,
                accountId: accountId
            )
            let reconstructed = Draft(
                id: draftLocalID,
                remoteID: email.id,
                identityID: matchedIdentityID,
                threadID: email.threadId,
                inReplyToMessageID: email.inReplyTo?.first,
                to: (email.to ?? []).map { $0.toCorrespondent() },
                cc: (email.cc ?? []).map { $0.toCorrespondent() },
                bcc: (email.bcc ?? []).map { $0.toCorrespondent() },
                subject: email.subject ?? "",
                htmlBody: htmlBody,
                attachmentIDs: stagedAttachments.map(\.id)
            )
            lock.withLock {
                for attachment in stagedAttachments {
                    stagedAttachmentsByID[attachment.id] = attachment
                }
                stagedDraftsByRemoteID[email.id] = reconstructed
                stagedDraftsByLocalID[draftLocalID] = reconstructed
                remoteDraftIDByLocalID[draftLocalID] = email.id
            }
            return reconstructed
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Source-scoped draft lookup validating account ownership before returning or restoring a staged draft.
    public func draft(for messageID: String, sourceID: MailSourceID) async throws -> Draft? {
        try validateSource(sourceID)
        return try await draft(for: messageID)
    }

    /// Read-only access to locally staged canonical draft attachments without performing network I/O.
    public func localDraftAttachments(for draft: Draft) async throws -> [MIMEMessageAttachment] {
        try lock.withLock {
            let canonical: Draft? = if let remoteID = draft.remoteID, let byRemote = stagedDraftsByRemoteID[remoteID] {
                byRemote
            } else if let remoteID = remoteDraftIDByLocalID[draft.id], let byRemote = stagedDraftsByRemoteID[remoteID] {
                byRemote
            } else {
                stagedDraftsByLocalID[draft.id]
            }
            guard canonical == draft else {
                throw MailBackendError.notFound(id: draft.id)
            }
            var result: [MIMEMessageAttachment] = []
            for id in draft.attachmentIDs {
                guard let staged = stagedAttachmentsByID[id], staged.draftID == draft.id else {
                    throw MailBackendError.notFound(id: id)
                }
                result.append(
                    MIMEMessageAttachment(
                        id: staged.id,
                        filename: staged.filename,
                        mimeType: staged.mimeType,
                        data: staged.data,
                        isInline: staged.contentID != nil,
                        contentID: staged.contentID
                    )
                )
            }
            return result
        }
    }

    /// Source-scoped read-only access to locally staged canonical draft attachments.
    public func localDraftAttachments(for draft: Draft, sourceID: MailSourceID) async throws -> [MIMEMessageAttachment] {
        try validateSource(sourceID)
        return try await localDraftAttachments(for: draft)
    }

    /// Destroys a remote JMAP draft (resolving restored local draft IDs to their canonical server ID) and clears staging.
    public func discard(draftID: String) async throws {
        let (session, accountId) = try requireConnectedSession()
        enum DiscardTarget {
            case remote(remoteID: String, localID: String?)
            case localOnly(localID: String)
        }
        let target: DiscardTarget = lock.withLock {
            if let mappedRemoteID = remoteDraftIDByLocalID[draftID] {
                return .remote(remoteID: mappedRemoteID, localID: draftID)
            }
            if let stagedByRemote = stagedDraftsByRemoteID[draftID] {
                return .remote(remoteID: draftID, localID: stagedByRemote.id)
            }
            if let matching = stagedDraftsByRemoteID.first(where: { $0.value.id == draftID }) {
                return .remote(remoteID: matching.key, localID: draftID)
            }
            if let localOnly = stagedDraftsByLocalID[draftID], localOnly.remoteID == nil {
                return .localOnly(localID: draftID)
            }
            if UUID(uuidString: draftID) == nil || emailsByID[draftID] != nil {
                return .remote(remoteID: draftID, localID: nil)
            }
            return .localOnly(localID: draftID)
        }

        switch target {
        case .localOnly(let localID):
            lock.withLock {
                stagedDraftsByLocalID.removeValue(forKey: localID)
                remoteDraftIDByLocalID.removeValue(forKey: localID)
                stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != localID }
            }
            return
        case .remote(let remoteID, let localID):
            do {
                _ = try await client.setEmails(
                    session: session,
                    accountId: accountId,
                    destroy: [remoteID]
                )
            } catch let error as JMAPError {
                if case .notFound = error {
                    // Remote draft was already removed on the server; proceed to clear local staging.
                } else {
                    recordSyncFailure(error)
                    throw error.asMailBackendError()
                }
            }
            var removedFromFolders: [String] = []
            lock.withLock {
                stagedDraftsByRemoteID.removeValue(forKey: remoteID)
                if let localID {
                    stagedDraftsByLocalID.removeValue(forKey: localID)
                    remoteDraftIDByLocalID.removeValue(forKey: localID)
                    stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != localID }
                } else {
                    stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != draftID }
                }
                emailsByID.removeValue(forKey: remoteID)
                bodiesByID.removeValue(forKey: remoteID)
                rawSourceDataByID.removeValue(forKey: remoteID)
                for (folderID, list) in headersByFolderID where list.contains(where: { $0.id == remoteID }) {
                    headersByFolderID[folderID] = list.filter { $0.id != remoteID }
                    removedFromFolders.append(folderID)
                }
            }
            for folderID in removedFromFolders {
                broadcast(.messagesRemoved(folderID: folderID, messageIDs: [remoteID]))
            }
            if let draftsMailboxID = lock.withLock({ mailboxesByID.values.first(where: { $0.folderRole == .drafts })?.id }) {
                broadcast(.folderRefreshed(folderID: draftsMailboxID))
            }
        }
    }

    /// Source-scoped draft discard validating account ownership.
    public func discard(draftID: String, sourceID: MailSourceID) async throws {
        try validateSource(sourceID)
        try await discard(draftID: draftID)
    }

    /// Sends a draft using `Identity/get` + batched `Email/set` + `EmailSubmission/set`, moving the sent copy to Sent.
    ///
    /// Keeps any previously saved draft intact until submission succeeds so retries never lose the draft,
    /// and reports post-delivery cleanup issues as non-fatal `SendResultWarning` entries.
    public func send(draft: Draft) async throws -> SendResult {
        let allRecipients = (draft.to + draft.cc + draft.bcc)
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !allRecipients.isEmpty else {
            throw DraftValidationError.missingRecipients
        }

        let (session, accountId) = try requireConnectedSession()
        let (draftsMailbox, sentMailbox) = lock.withLock {
            (
                mailboxesByID.values.first(where: { $0.folderRole == .drafts }),
                mailboxesByID.values.first(where: { $0.folderRole == .sent })
            )
        }
        guard let targetSentMailbox = sentMailbox ?? draftsMailbox else {
            throw JMAPError.missingSentMailbox.asMailBackendError()
        }
        let stagingMailboxID = draftsMailbox?.id ?? targetSentMailbox.id

        do {
            guard let identity = try await resolveIdentity(for: draft, session: session, accountId: accountId) else {
                throw JMAPError.missingIdentity
            }
            let uploadedAttachments = try await uploadStagedAttachments(
                for: draft,
                session: session,
                accountId: accountId
            )
            let emailObject = buildEmailCreateObject(
                draft: draft,
                mailboxID: stagingMailboxID,
                fromAddress: JMAPEmailAddress(
                    name: identity.name.isEmpty ? account.displayName : identity.name,
                    email: identity.email
                ),
                isDraft: true,
                attachments: uploadedAttachments
            )
            var onSuccessPatch: [String: JMAPJSONValue] = [
                "keywords/$draft": .null,
                "keywords/$seen": .bool(true)
            ]
            if stagingMailboxID != targetSentMailbox.id {
                onSuccessPatch["mailboxIds/\(stagingMailboxID)"] = .null
                onSuccessPatch["mailboxIds/\(targetSentMailbox.id)"] = .bool(true)
            }

            let (emailSet, _, _, onSuccessUpdateFailed) = try await client.createAndSubmitEmail(
                session: session,
                accountId: accountId,
                creationID: "draft",
                emailObject: emailObject,
                identityId: identity.id,
                mailFrom: identity.email,
                rcptTo: allRecipients,
                onSuccessUpdateEmail: onSuccessPatch
            )
            let sentMessageID = emailSet.created?["draft"]?["id"]?.stringValue
            var warnings: [SendResultWarning] = []
            if onSuccessUpdateFailed {
                warnings.append(.sentCopyAppendFailed)
            }

            // Destroy the prior saved draft only AFTER submission is confirmed.
            // Never turn a post-delivery cleanup error into a failed send.
            let priorRemoteID = draft.remoteID ?? lock.withLock { remoteDraftIDByLocalID[draft.id] }
            if let priorRemoteID, !priorRemoteID.isEmpty, priorRemoteID != sentMessageID {
                do {
                    _ = try await client.setEmails(
                        session: session,
                        accountId: accountId,
                        destroy: [priorRemoteID]
                    )
                } catch let error as JMAPError {
                    if case .notFound = error {
                        // Already deleted on the server.
                    } else {
                        warnings.append(.remoteDraftCleanupFailed)
                    }
                } catch {
                    warnings.append(.remoteDraftCleanupFailed)
                }
            }

            lock.withLock {
                if let priorRemoteID {
                    stagedDraftsByRemoteID.removeValue(forKey: priorRemoteID)
                }
                stagedDraftsByLocalID.removeValue(forKey: draft.id)
                remoteDraftIDByLocalID.removeValue(forKey: draft.id)
                stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != draft.id }
            }
            broadcast(.folderRefreshed(folderID: targetSentMailbox.id))
            return SendResult(sentMessageID: sentMessageID, warnings: warnings)
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    // MARK: - Aliases & Signatures

    /// Lists server-side sending identities mapped to `ServerAlias`.
    public func listAliases() async throws -> [ServerAlias] {
        let (session, accountId) = try requireConnectedSession()
        let cached = lock.withLock { identities }
        let list: [JMAPIdentity]
        if !cached.isEmpty {
            list = cached
        } else {
            do {
                let response = try await client.getIdentities(session: session, accountId: accountId)
                lock.withLock { identities = response.list }
                list = response.list
            } catch let error as JMAPError {
                throw error.asMailBackendError()
            }
        }
        return list.enumerated().map { index, identity in
            ServerAlias(
                id: identity.id,
                email: identity.email,
                displayName: identity.name.isEmpty ? nil : identity.name,
                isDefault: identity.email.caseInsensitiveCompare(account.emailAddress) == .orderedSame || index == 0
            )
        }
    }

    /// Lists server-side identity signatures mapped to `ServerSignature`.
    public func listServerSignatures() async throws -> [ServerSignature] {
        let (session, accountId) = try requireConnectedSession()
        let cached = lock.withLock { identities }
        let list: [JMAPIdentity]
        if !cached.isEmpty {
            list = cached
        } else {
            do {
                let response = try await client.getIdentities(session: session, accountId: accountId)
                lock.withLock { identities = response.list }
                list = response.list
            } catch let error as JMAPError {
                throw error.asMailBackendError()
            }
        }
        return list.compactMap { identity in
            let body = identity.htmlSignature.isEmpty ? identity.textSignature : identity.htmlSignature
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let name = identity.name.isEmpty ? identity.email : identity.name
            return ServerSignature(
                id: identity.id,
                name: name,
                body: body,
                isDefault: identity.email.caseInsensitiveCompare(account.emailAddress) == .orderedSame
            )
        }
    }

    // MARK: - Search

    /// Runs server-side structured RFC 8621 `Email/query` search (or local cache-only search when requested).
    public func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        if query.execution == .cacheOnly {
            let allCached = lock.withLock { headersByFolderID.values.flatMap { $0 } }
            var seen: Set<String> = []
            return allCached
                .filter { seen.insert($0.id).inserted && query.matches($0) }
                .sorted { $0.date > $1.date }
        }
        let (session, accountId) = try requireConnectedSession()
        let filter = Self.buildSearchFilter(for: query)
        let pageLimit = max(1, min(500, session.maxObjectsInGet ?? 500))
        let fallbackFolderID = query.folderID ?? lock.withLock {
            mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.id
        } ?? ""
        do {
            var position = 0
            var seenIDs: Set<String> = []
            var headers: [MessageHeader] = []
            while true {
                try Task.checkCancellation()
                let (queryResponse, getResponse) = try await client.queryAndGetEmails(
                    session: session,
                    accountId: accountId,
                    filter: filter,
                    position: position,
                    limit: pageLimit
                )
                guard !queryResponse.ids.isEmpty else { break }
                let byID = Dictionary(uniqueKeysWithValues: getResponse.list.map { ($0.id, $0) })
                var addedOnPage = 0
                for id in queryResponse.ids where seenIDs.insert(id).inserted {
                    addedOnPage += 1
                    guard let email = byID[id] else { continue }
                    let folderID = query.folderID
                        ?? email.mailboxIds.first(where: { $0.value })?.key
                        ?? fallbackFolderID
                    headers.append(email.toMessageHeader(folderID: folderID))
                }
                let nextPosition = queryResponse.position + queryResponse.ids.count
                // Guard against buggy servers that ignore `position` or repeat pages forever.
                guard nextPosition > position, addedOnPage > 0 else { break }
                position = nextPosition
                if let total = queryResponse.total, position >= total {
                    break
                }
            }
            return headers
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Builds an RFC 8621 §4.4.1 `FilterCondition` / `FilterOperator` JSON dictionary from `SearchQuery`.
    public static func buildSearchFilter(for query: SearchQuery) -> [String: JMAPJSONValue] {
        var condition: [String: JMAPJSONValue] = [:]
        let trimmedText = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            condition["text"] = .string(trimmedText)
        }
        if let from = query.from?.trimmingCharacters(in: .whitespacesAndNewlines), !from.isEmpty {
            condition["from"] = .string(from)
        }
        if let to = query.to?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty {
            condition["to"] = .string(to)
        }
        if let subject = query.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            condition["subject"] = .string(subject)
        }
        if let hasAttachments = query.hasAttachments {
            condition["hasAttachment"] = .bool(hasAttachments)
        }
        if let dateRange = query.dateRange {
            condition["after"] = .string(JMAPDateCoding.formatUTC(dateRange.lowerBound))
            condition["before"] = .string(JMAPDateCoding.formatUTC(dateRange.upperBound))
        }
        if let isUnread = query.isUnread {
            if isUnread {
                condition["notKeyword"] = .string("$seen")
            } else {
                condition["hasKeyword"] = .string("$seen")
            }
        }
        var extraClauses: [[String: JMAPJSONValue]] = []
        if let isFlagged = query.isFlagged {
            let flagKey = isFlagged ? "hasKeyword" : "notKeyword"
            if condition[flagKey] == nil {
                condition[flagKey] = .string("$flagged")
            } else {
                extraClauses.append([flagKey: .string("$flagged")])
            }
        }
        if let folderID = query.folderID {
            condition["inMailbox"] = .string(folderID)
        } else if let folderIDs = query.folderIDs, !folderIDs.isEmpty {
            if folderIDs.count == 1, let single = folderIDs.first {
                condition["inMailbox"] = .string(single)
            } else {
                extraClauses.append([
                    "operator": .string("OR"),
                    "conditions": .array(folderIDs.sorted().map { .object(["inMailbox": .string($0)]) })
                ])
            }
        }

        if extraClauses.isEmpty {
            return condition
        }
        var allConditions: [JMAPJSONValue] = []
        if !condition.isEmpty {
            allConditions.append(.object(condition))
        }
        allConditions.append(contentsOf: extraClauses.map { .object($0) })
        return [
            "operator": .string("AND"),
            "conditions": .array(allConditions)
        ]
    }

    // MARK: - Calendar (Capability-Gated)

    /// JMAP Mail does not implement server-side ICS rendering; views fall back to local parsing.
    public func calendarEvent(from _: String) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(.serverSideIcsRender)
    }

    /// JMAP Mail does not implement server-side calendar replies; views fall back to iMIP REPLY.
    public func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {
        throw MailBackendError.notSupported(.serverSideCalendarReply)
    }

    // MARK: - Cached Reads & Extension Services

    /// Returns cached headers for `folder` without performing any network request.
    public func cachedMessageHeaders(in folder: Folder, sourceID _: MailSourceID) async throws -> [MessageHeader] {
        lock.withLock { headersByFolderID[folder.id] ?? [] }
    }

    /// Returns one cached header without performing any network request.
    public func cachedMessageHeader(messageID: MessageHeader.ID, folderID: Folder.ID) async -> MessageHeader? {
        lock.withLock {
            headersByFolderID[folderID]?.first(where: { $0.id == messageID })
        }
    }

    /// Returns Inbox message IDs observed as genuine fresh deliveries at or after `since`.
    public func freshDeliveryMessageIDs(since: Date) async -> Set<MessageHeader.ID> {
        lock.withLock {
            Set(freshDeliveryTimestamps.compactMap { id, arrivedAt in
                arrivedAt >= since ? id : nil
            })
        }
    }

    /// Returns a locally cached body without performing any network request.
    public func cachedBody(for messageID: MessageHeader.ID, sourceID _: MailSourceID?) async -> MessageBody? {
        lock.withLock { bodiesByID[messageID] }
    }

    /// Returns cached `List-Unsubscribe` options without performing any network request.
    public func cachedListUnsubscribe(
        for messageID: MessageHeader.ID,
        sourceID _: MailSourceID
    ) async -> ListUnsubscribeOptions? {
        lock.withLock { bodiesByID[messageID]?.listUnsubscribe }
    }

    /// Returns cached bulk-precedence status without performing any network request.
    public func cachedIsBulkPrecedence(
        for messageID: MessageHeader.ID,
        sourceID _: MailSourceID
    ) async -> Bool {
        lock.withLock { bodiesByID[messageID]?.isBulkPrecedence ?? false }
    }

    /// Runs a bounded incremental sync for background refresh and closed-app push wakes (`PushWakeCoordinator`).
    public func refreshMailbox(for _: MailSourceID) async throws {
        _ = try requireConnectedSession()
        let inboxFolder = lock.withLock {
            mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.toFolder()
        }
        do {
            let didFullRefresh = try await performDeltaSync(fallbackFolder: inboxFolder)
            if !didFullRefresh, let inboxFolder, lock.withLock({ headersByFolderID[inboxFolder.id] == nil }) {
                _ = try await fetchMessagesPage(in: inboxFolder, pageToken: nil)
            }
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Reports current JMAP connection and sync health for Settings diagnostics.
    public func syncHealth(for sourceID: MailSourceID) async -> AccountSyncHealth {
        lock.withLock {
            let state: SyncHealthState
            if lastSyncRequiresReauth {
                state = .authenticationRequired
            } else if lastSyncError != nil {
                state = .providerError
            } else if isConnected {
                state = .healthy
            } else {
                state = .offline
            }
            let cachedCount = emailsByID.count
            return AccountSyncHealth(
                sourceID: sourceID,
                state: state,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastErrorDescription: lastSyncError,
                indexStatus: .ready(messageCount: cachedCount),
                cacheSizeBytes: 0,
                pendingMutationCount: 0
            )
        }
    }

    // MARK: - Live Updates (EventSource SSE)

    /// Returns a multiplexed stream of coarse `MailEvent` notifications backed by RFC 8620 §7.3 `EventSource`.
    public func subscribeToChanges() -> AsyncStream<MailEvent> {
        let token = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                subscribers[token] = continuation
            }
            startEventSourceIfNeeded()
            continuation.onTermination = { [weak self] _ in
                self?.removeSubscriber(token)
            }
        }
    }

    // MARK: - JMAP WebPush (RFC 8620 §7.2)

    /// Registers an RFC 8620 §7.2 `PushSubscription` on the connected JMAP session using `JMAPWebPushSubscriptionSpec`.
    public func registerWebPushSubscription(
        spec: JMAPWebPushSubscriptionSpec
    ) async throws -> PushRelayRegistrationResponse {
        let (session, _) = try requireConnectedSession()
        let requestData = try spec.encodedSetCreateRequestData(clientCreationID: "brev-push-sub", callID: "p0")
        let response = try await client.sendPushSubscriptionRequest(session: session, requestData: requestData)
        let invocation = try response.response(forCallID: "p0")
        let setResponse = try invocation.decodeArguments(JMAPSetResponse.self)
        if let notCreated = setResponse.notCreated?.values.first {
            throw JMAPError.methodError(type: notCreated.type, description: notCreated.description)
        }
        guard let created = setResponse.created?["brev-push-sub"],
              let subscriptionID = created["id"]?.stringValue,
              !subscriptionID.isEmpty
        else {
            throw JMAPError.invalidResponse
        }
        let expires = created["expires"]?.stringValue.flatMap(JMAPDateCoding.parse)
        let verificationCode = created["verificationCode"]?.stringValue
        return PushRelayRegistrationResponse(
            subscriptionID: subscriptionID,
            expiresAt: expires,
            verificationCode: verificationCode,
            state: .pendingVerification
        )
    }

    /// Completes an RFC 8620 §7.2.2 `PushVerification` challenge for an active pending subscription.
    public func verifyWebPushSubscription(
        subscriptionID: String,
        verificationCode: String
    ) async throws -> PushRelayRegistrationResponse {
        let (session, _) = try requireConnectedSession()
        let requestData = try JMAPWebPushSubscriptionSpec.encodedSetVerifyRequestData(
            subscriptionID: subscriptionID,
            verificationCode: verificationCode,
            callID: "pv0"
        )
        let response = try await client.sendPushSubscriptionRequest(session: session, requestData: requestData)
        let invocation = try response.response(forCallID: "pv0")
        let setResponse = try invocation.decodeArguments(JMAPSetResponse.self)
        if let notUpdated = setResponse.notUpdated?.values.first {
            throw JMAPError.methodError(type: notUpdated.type, description: notUpdated.description)
        }
        return PushRelayRegistrationResponse(
            subscriptionID: subscriptionID,
            expiresAt: nil,
            verificationCode: nil,
            state: .active
        )
    }

    /// Destroys a registered RFC 8620 §7.2 `PushSubscription` on the connected JMAP server.
    public func unregisterWebPushSubscription(subscriptionID: String) async throws {
        let (session, _) = try requireConnectedSession()
        let requestData = try JMAPWebPushSubscriptionSpec.encodedSetDestroyRequestData(
            subscriptionID: subscriptionID,
            callID: "pd0"
        )
        let response = try await client.sendPushSubscriptionRequest(session: session, requestData: requestData)
        let invocation = try response.response(forCallID: "pd0")
        let setResponse = try invocation.decodeArguments(JMAPSetResponse.self)
        if let notDestroyed = setResponse.notDestroyed?.values.first, notDestroyed.type != "notFound" {
            throw JMAPError.methodError(type: notDestroyed.type, description: notDestroyed.description)
        }
    }

    // MARK: - Internal Helpers

    private func requireConnectedSession() throws -> (JMAPSession, String) {
        try lock.withLock {
            guard isConnected, let session, let primaryAccountID else {
                throw MailBackendError.notConnected
            }
            return (session, primaryAccountID)
        }
    }

    private func validateSource(_ sourceID: MailSourceID) throws {
        guard sourceID.accountID == account.id else {
            throw MailBackendError.notFound(id: sourceID.accountID)
        }
    }

    private func fetchMessagesPage(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        let (session, accountId) = try requireConnectedSession()
        let position = pageToken.flatMap(Int.init) ?? 0
        do {
            let (query, get) = try await client.queryAndGetEmails(
                session: session,
                accountId: accountId,
                filter: ["inMailbox": .string(folder.id)],
                position: position,
                limit: Self.pageSize
            )
            let byID = Dictionary(uniqueKeysWithValues: get.list.map { ($0.id, $0) })
            let headers = query.ids.compactMap { id -> MessageHeader? in
                byID[id]?.toMessageHeader(folderID: folder.id)
            }
            let nextOffset = query.position + query.ids.count
            let nextToken: String?
            if let total = query.total {
                nextToken = nextOffset < total ? String(nextOffset) : nil
            } else {
                nextToken = query.ids.count >= Self.pageSize ? String(nextOffset) : nil
            }
            let timestamp = now()
            lock.withLock {
                // Seed the reconciled emailState only when establishing the initial baseline
                // (or immediately after full invalidation); never advance an existing delta cursor
                // on a single-folder page read.
                if position == 0, emailState == nil, !get.state.isEmpty {
                    emailState = get.state
                }
                for email in get.list {
                    emailsByID[email.id] = email
                }
                if position == 0 {
                    headersByFolderID[folder.id] = headers
                } else {
                    var existing = headersByFolderID[folder.id] ?? []
                    let existingIDs = Set(existing.map(\.id))
                    existing.append(contentsOf: headers.filter { !existingIDs.contains($0.id) })
                    headersByFolderID[folder.id] = existing
                }
                lastSuccessfulSyncAt = timestamp
                lastSyncError = nil
                lastSyncRequiresReauth = false
            }
            return (headers, nextToken)
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Performs incremental `Mailbox/changes` + `Email/changes` delta sync.
    /// Returns `true` when a full refresh fallback ran (e.g. after `cannotCalculateChanges`).
    @discardableResult
    private func performDeltaSync(fallbackFolder: Folder?) async throws -> Bool {
        let (session, accountId) = try requireConnectedSession()
        let (priorMailboxState, priorEmailState) = lock.withLock { (mailboxState, emailState) }

        var fellBackToFull = false
        let maxChangePages = 50

        // 1. Mailbox delta sync.
        let getBatchLimit = max(1, min(500, session.maxObjectsInGet ?? 500))
        if let initialMailboxState = priorMailboxState, !initialMailboxState.isEmpty {
            do {
                var sinceState = initialMailboxState
                for _ in 0 ..< maxChangePages {
                    let mbChanges = try await client.mailboxChanges(
                        session: session,
                        accountId: accountId,
                        sinceState: sinceState
                    )
                    let changedMailboxIDs = Array(Set(mbChanges.created + mbChanges.updated))
                    var fetchedMailboxes: [JMAPMailbox] = []
                    for chunk in Self.chunked(changedMailboxIDs, maxSize: getBatchLimit) {
                        let fetched = try await client.getMailboxes(
                            session: session,
                            accountId: accountId,
                            ids: chunk
                        )
                        fetchedMailboxes.append(contentsOf: fetched.list)
                    }
                    // Commit updated mailboxes and advance mailboxState only after every chunk succeeds.
                    lock.withLock {
                        for mailbox in fetchedMailboxes {
                            mailboxesByID[mailbox.id] = mailbox
                        }
                        for destroyedID in mbChanges.destroyed {
                            mailboxesByID.removeValue(forKey: destroyedID)
                            headersByFolderID.removeValue(forKey: destroyedID)
                        }
                        mailboxState = mbChanges.newState
                    }
                    guard mbChanges.hasMoreChanges, mbChanges.newState != sinceState else { break }
                    sinceState = mbChanges.newState
                }
            } catch JMAPError.cannotCalculateChanges {
                fellBackToFull = true
                let allMailboxes = try await client.getMailboxes(session: session, accountId: accountId)
                lock.withLock {
                    mailboxState = allMailboxes.state
                    mailboxesByID = Dictionary(uniqueKeysWithValues: allMailboxes.list.map { ($0.id, $0) })
                }
            }
        } else {
            let allMailboxes = try await client.getMailboxes(session: session, accountId: accountId)
            lock.withLock {
                mailboxState = allMailboxes.state
                mailboxesByID = Dictionary(uniqueKeysWithValues: allMailboxes.list.map { ($0.id, $0) })
            }
        }

        // 2. Email delta sync.
        if let initialEmailState = priorEmailState, !initialEmailState.isEmpty {
            do {
                var sinceState = initialEmailState
                for _ in 0 ..< maxChangePages {
                    let changes = try await client.emailChanges(
                        session: session,
                        accountId: accountId,
                        sinceState: sinceState
                    )
                    try await applyEmailChanges(changes, session: session, accountId: accountId)
                    guard changes.hasMoreChanges, changes.newState != sinceState else { break }
                    sinceState = changes.newState
                }
            } catch JMAPError.cannotCalculateChanges {
                fellBackToFull = true
                // Invalidate all cached folder header lists and clear the delta cursor before rebuilding
                // so no previously cached folder retains stale state behind a newer cursor.
                lock.withLock {
                    emailState = nil
                    headersByFolderID.removeAll()
                }
                let targetFolder = fallbackFolder ?? lock.withLock {
                    mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.toFolder()
                }
                if let targetFolder {
                    _ = try await fetchMessagesPage(in: targetFolder, pageToken: nil)
                }
            }
        } else if let targetFolder = fallbackFolder ?? lock.withLock({
            mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.toFolder()
        }) {
            fellBackToFull = true
            _ = try await fetchMessagesPage(in: targetFolder, pageToken: nil)
        }

        let timestamp = now()
        lock.withLock {
            lastSuccessfulSyncAt = timestamp
            lastSyncError = nil
            lastSyncRequiresReauth = false
        }
        return fellBackToFull
    }

    private func applyEmailChanges(
        _ changes: JMAPChangesResponse,
        session: JMAPSession,
        accountId: String
    ) async throws {
        let fetchIDs = Array(Set(changes.created + changes.updated))
        let getBatchLimit = max(1, min(500, session.maxObjectsInGet ?? 500))
        var fetchedEmails: [JMAPEmail] = []
        for chunk in Self.chunked(fetchIDs, maxSize: getBatchLimit) {
            let getResponse = try await client.getEmails(
                session: session,
                accountId: accountId,
                ids: chunk,
                properties: JMAPClient.headerProperties
            )
            fetchedEmails.append(contentsOf: getResponse.list)
        }

        let createdSet = Set(changes.created)
        let destroyedSet = Set(changes.destroyed)
        let timestamp = now()
        var addedByFolder: [String: [String]] = [:]
        var updatedByFolder: [String: [String]] = [:]
        var removedByFolder: [String: [String]] = [:]

        lock.withLock {
            emailState = changes.newState
            let inboxID = mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.id

            for destroyedID in destroyedSet {
                emailsByID.removeValue(forKey: destroyedID)
                bodiesByID.removeValue(forKey: destroyedID)
                rawSourceDataByID.removeValue(forKey: destroyedID)
                for (folderID, list) in headersByFolderID {
                    if list.contains(where: { $0.id == destroyedID }) {
                        headersByFolderID[folderID] = list.filter { $0.id != destroyedID }
                        removedByFolder[folderID, default: []].append(destroyedID)
                    }
                }
            }

            for email in fetchedEmails {
                emailsByID[email.id] = email
                let activeFolderIDs = Set(email.mailboxIds.compactMap { $0.value ? $0.key : nil })

                // Remove from folders where this email is no longer present.
                for (folderID, list) in headersByFolderID where !activeFolderIDs.contains(folderID) {
                    if list.contains(where: { $0.id == email.id }) {
                        headersByFolderID[folderID] = list.filter { $0.id != email.id }
                        removedByFolder[folderID, default: []].append(email.id)
                    }
                }

                // Upsert into every current mailbox membership.
                for folderID in activeFolderIDs {
                    let header = email.toMessageHeader(folderID: folderID)
                    var list = headersByFolderID[folderID] ?? []
                    if let existingIndex = list.firstIndex(where: { $0.id == email.id }) {
                        list[existingIndex] = header
                        updatedByFolder[folderID, default: []].append(email.id)
                    } else {
                        list.insert(header, at: 0)
                        list.sort { $0.date > $1.date }
                        addedByFolder[folderID, default: []].append(email.id)
                        if folderID == inboxID, createdSet.contains(email.id) {
                            freshDeliveryTimestamps[email.id] = timestamp
                        }
                    }
                    headersByFolderID[folderID] = list
                }
            }
        }

        for (folderID, ids) in removedByFolder {
            broadcast(.messagesRemoved(folderID: folderID, messageIDs: ids))
        }
        for (folderID, ids) in addedByFolder {
            broadcast(.messagesAdded(folderID: folderID, messageIDs: ids))
        }
        for (folderID, ids) in updatedByFolder {
            broadcast(.messagesUpdated(folderID: folderID, messageIDs: ids))
        }
    }

    private func startEventSourceIfNeeded() {
        let shouldStart: Bool = lock.withLock {
            guard isConnected,
                  !subscribers.isEmpty,
                  eventSourceTask == nil,
                  let eventURL = session?.eventSourceUrl,
                  !eventURL.isEmpty
            else {
                return false
            }
            return true
        }
        guard shouldStart else { return }

        let task = Task { [weak self] in
            var consecutiveInterruptions = 0
            var needsReconnectCatchUp = false
            while !Task.isCancelled {
                guard let self else { break }
                let activeSession: (JMAPSession, String)? = lock.withLock {
                    guard self.isConnected, !self.subscribers.isEmpty,
                          let session = self.session,
                          let primaryAccountID = self.primaryAccountID
                    else {
                        return nil
                    }
                    return (session, primaryAccountID)
                }
                guard let (session, accountId) = activeSession else { break }

                do {
                    let stream = try await client.openEventSource(session: session)
                    if needsReconnectCatchUp {
                        // Reconcile any mail delivered during the EventSource disconnect gap
                        // even if no further SSE state frame arrives after reconnection.
                        do {
                            _ = try await performDeltaSync(fallbackFolder: nil)
                            needsReconnectCatchUp = false
                        } catch JMAPError.authenticationRequired {
                            throw JMAPError.authenticationRequired
                        } catch {
                            // Keep needsReconnectCatchUp armed so the next reconnect retries.
                        }
                    }
                    for try await event in stream {
                        if Task.isCancelled { break }
                        consecutiveInterruptions = 0
                        guard event.event == "state" || event.event == nil,
                              let data = event.data.data(using: .utf8),
                              let stateChange = try? JSONDecoder().decode(JMAPStateChange.self, from: data),
                              let accountChanges = stateChange.changed[accountId],
                              accountChanges["Email"] != nil || accountChanges["Mailbox"] != nil
                        else {
                            continue
                        }
                        _ = try? await performDeltaSync(fallbackFolder: nil)
                    }
                    if Task.isCancelled { break }
                    // Stream closed cleanly (EOF / server recycle): reconcile on reconnect with bounded backoff.
                    needsReconnectCatchUp = true
                    consecutiveInterruptions += 1
                    let delay = eventSourceRetryDelay(consecutiveInterruptions)
                    try? await Task.sleep(nanoseconds: delay)
                } catch is CancellationError {
                    break
                } catch JMAPError.authenticationRequired {
                    recordSyncFailure(.authenticationRequired)
                    break
                } catch {
                    needsReconnectCatchUp = true
                    consecutiveInterruptions += 1
                    let delay = eventSourceRetryDelay(consecutiveInterruptions)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
            self?.lock.withLock {
                self?.eventSourceTask = nil
            }
        }
        lock.withLock {
            if eventSourceTask == nil {
                eventSourceTask = task
            } else {
                task.cancel()
            }
        }
    }

    private func removeSubscriber(_ token: UUID) {
        let taskToCancel: Task<Void, Never>? = lock.withLock {
            subscribers.removeValue(forKey: token)
            guard subscribers.isEmpty else { return nil }
            let existing = eventSourceTask
            eventSourceTask = nil
            return existing
        }
        taskToCancel?.cancel()
    }

    private func broadcast(_ event: MailEvent) {
        let active = lock.withLock { Array(subscribers.values) }
        for continuation in active {
            continuation.yield(event)
        }
    }

    private func updateCachedHeaders(
        messageIDs: Set<String>,
        mutate: (inout MessageHeader) -> Void
    ) -> [String] {
        lock.withLock {
            var affected: [String] = []
            for (folderID, var list) in headersByFolderID {
                var didMutate = false
                for index in list.indices where messageIDs.contains(list[index].id) {
                    mutate(&list[index])
                    didMutate = true
                }
                if didMutate {
                    headersByFolderID[folderID] = list
                    affected.append(folderID)
                }
            }
            return affected
        }
    }

    private func resolveIdentity(
        for draft: Draft,
        session: JMAPSession,
        accountId: String
    ) async throws -> JMAPIdentity? {
        let cached = lock.withLock { identities }
        let candidates: [JMAPIdentity]
        if !cached.isEmpty {
            candidates = cached
        } else {
            let response = try await client.getIdentities(session: session, accountId: accountId)
            lock.withLock { identities = response.list }
            candidates = response.list
        }
        if let requestedID = draft.identityID,
           let matched = candidates.first(where: { $0.id == requestedID }) {
            return matched
        }
        if let matchedEmail = candidates.first(where: {
            $0.email.caseInsensitiveCompare(account.emailAddress) == .orderedSame
        }) {
            return matchedEmail
        }
        return candidates.first
    }

    private func resolveIdentityID(
        forFromAddress fromAddress: JMAPEmailAddress?,
        session: JMAPSession,
        accountId: String
    ) async throws -> String? {
        guard let rawEmail = fromAddress?.email.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawEmail.isEmpty
        else {
            return nil
        }
        let cached = lock.withLock { identities }
        let candidates: [JMAPIdentity]
        if !cached.isEmpty {
            candidates = cached
        } else if session.supportsSubmission {
            let response = try await client.getIdentities(session: session, accountId: accountId)
            lock.withLock { identities = response.list }
            candidates = response.list
        } else {
            candidates = []
        }
        let emailMatches = candidates.filter {
            $0.email.caseInsensitiveCompare(rawEmail) == .orderedSame
        }
        if emailMatches.count == 1 {
            return emailMatches[0].id
        }
        if emailMatches.count > 1,
           let rawName = fromAddress?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            let nameMatches = emailMatches.filter {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(rawName) == .orderedSame
            }
            if nameMatches.count == 1 {
                return nameMatches[0].id
            }
        }
        return nil
    }

    private static func escapedHTMLFromPlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func normalizedContentID(_ raw: String) -> String {
        var value = (raw.removingPercentEncoding ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<") {
            value.removeFirst()
        }
        if value.hasSuffix(">") {
            value.removeLast()
        }
        return value.lowercased()
    }

    private static func referencedContentIDs(inHTML html: String) -> Set<String> {
        let pattern = #"(?i)\bcid:([^"'\s<>)]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        var result: Set<String> = []
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            let normalized = normalizedContentID(String(html[captureRange]))
            if !normalized.isEmpty {
                result.insert(normalized)
            }
        }
        return result
    }

    private static func chunked<T>(_ items: [T], maxSize: Int) -> [[T]] {
        guard !items.isEmpty else { return [] }
        let limit = max(1, maxSize)
        var chunks: [[T]] = []
        var index = 0
        while index < items.count {
            let end = min(index + limit, items.count)
            chunks.append(Array(items[index ..< end]))
            index = end
        }
        return chunks
    }

    private func uploadStagedAttachments(
        for draft: Draft,
        session: JMAPSession,
        accountId: String
    ) async throws -> [(attachment: StagedAttachment, blobId: String)] {
        var uploaded: [(StagedAttachment, String)] = []
        for attachmentID in draft.attachmentIDs {
            guard let staged = lock.withLock({ stagedAttachmentsByID[attachmentID] }) else { continue }
            if let existingBlob = staged.uploadedBlobID {
                uploaded.append((staged, existingBlob))
                continue
            }
            let response = try await client.uploadBlob(
                session: session,
                accountId: accountId,
                data: staged.data,
                mimeType: staged.mimeType
            )
            lock.withLock {
                stagedAttachmentsByID[attachmentID]?.uploadedBlobID = response.blobId
            }
            uploaded.append((staged, response.blobId))
        }
        return uploaded
    }

    private func buildEmailCreateObject(
        draft: Draft,
        mailboxID: String,
        fromAddress: JMAPEmailAddress,
        isDraft: Bool,
        attachments: [(attachment: StagedAttachment, blobId: String)]
    ) -> [String: JMAPJSONValue] {
        var keywords: [String: JMAPJSONValue] = ["$seen": .bool(true)]
        if isDraft {
            keywords["$draft"] = .bool(true)
        }

        let plainBody = (try? HTMLTextStripper.visibleText(from: Data(draft.htmlBody.utf8))) ?? draft.htmlBody
        let isHTML = draft.htmlBody.contains("<") && draft.htmlBody.contains(">")
        var bodyValues: [String: JMAPJSONValue] = [
            "text": .object(["value": .string(plainBody)])
        ]
        let textBody: [JMAPJSONValue] = [
            .object(["partId": .string("text"), "type": .string("text/plain")])
        ]
        var htmlBody: [JMAPJSONValue] = []
        if isHTML {
            bodyValues["html"] = .object(["value": .string(draft.htmlBody)])
            htmlBody = [
                .object(["partId": .string("html"), "type": .string("text/html")])
            ]
        }

        var object: [String: JMAPJSONValue] = [
            "mailboxIds": .object([mailboxID: .bool(true)]),
            "keywords": .object(keywords),
            "from": .array([Self.encodeAddress(fromAddress)]),
            "subject": .string(draft.subject),
            "bodyValues": .object(bodyValues),
            "textBody": .array(textBody)
        ]
        if !htmlBody.isEmpty {
            object["htmlBody"] = .array(htmlBody)
        }
        if !draft.to.isEmpty {
            object["to"] = .array(draft.to.map { Self.encodeAddress(.from($0)) })
        }
        if !draft.cc.isEmpty {
            object["cc"] = .array(draft.cc.map { Self.encodeAddress(.from($0)) })
        }
        if !draft.bcc.isEmpty {
            object["bcc"] = .array(draft.bcc.map { Self.encodeAddress(.from($0)) })
        }
        if let inReplyTo = draft.inReplyToMessageID, !inReplyTo.isEmpty {
            object["inReplyTo"] = .array([.string(inReplyTo)])
            object["references"] = .array([.string(inReplyTo)])
        }
        if !attachments.isEmpty {
            object["attachments"] = .array(attachments.map { item in
                var entry: [String: JMAPJSONValue] = [
                    "blobId": .string(item.blobId),
                    "type": .string(item.attachment.mimeType),
                    "name": .string(item.attachment.filename),
                    "disposition": .string(item.attachment.contentID != nil ? "inline" : "attachment")
                ]
                if let cid = item.attachment.contentID {
                    entry["cid"] = .string(cid)
                }
                return .object(entry)
            })
        }
        return object
    }

    private static func encodeAddress(_ address: JMAPEmailAddress) -> JMAPJSONValue {
        var dict: [String: JMAPJSONValue] = ["email": .string(address.email)]
        if let name = address.name, !name.isEmpty {
            dict["name"] = .string(name)
        }
        return .object(dict)
    }

    private func recordSyncFailure(_ error: JMAPError) {
        lock.withLock {
            lastSyncError = error.localizedDescription
            lastSyncRequiresReauth = (error == .authenticationRequired || error == .missingToken)
        }
    }

    private static func sortedFolders(from mailboxes: [JMAPMailbox]) -> [Folder] {
        mailboxes
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { $0.toFolder() }
    }
}
