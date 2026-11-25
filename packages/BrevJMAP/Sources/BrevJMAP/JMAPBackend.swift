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
                if let newState = result.newState { mailboxState = newState }
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
            let result = try await client.setMailboxes(
                session: session,
                accountId: accountId,
                update: [id: ["name": .string(trimmedName)]]
            )
            let updatedMailbox: JMAPMailbox = lock.withLock {
                if let newState = result.newState { mailboxState = newState }
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
            let result = try await client.setMailboxes(
                session: session,
                accountId: accountId,
                destroy: [id]
            )
            lock.withLock {
                if let newState = result.newState { mailboxState = newState }
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
    public func flushFolder(id: Folder.ID) async throws {
        let (session, accountId) = try requireConnectedSession()
        do {
            var allDestroyed: [String] = []
            while true {
                let query = try await client.queryEmailIDs(
                    session: session,
                    accountId: accountId,
                    filter: ["inMailbox": .string(id)],
                    position: 0,
                    limit: 500
                )
                guard !query.ids.isEmpty else { break }
                let setResult = try await client.setEmails(
                    session: session,
                    accountId: accountId,
                    destroy: query.ids
                )
                lock.withLock {
                    if let newState = setResult.newState { emailState = newState }
                    for removedID in query.ids {
                        emailsByID.removeValue(forKey: removedID)
                        bodiesByID.removeValue(forKey: removedID)
                        rawSourceDataByID.removeValue(forKey: removedID)
                    }
                    headersByFolderID[id] = []
                }
                allDestroyed.append(contentsOf: query.ids)
                if query.ids.count < 500 { break }
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
                if !response.state.isEmpty { emailState = response.state }
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
            let response = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs), newState: response.newState) { header in
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
            let response = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs), newState: response.newState) { header in
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
            let response = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let affectedFolders = updateCachedHeaders(messageIDs: Set(messageIDs), newState: response.newState) { header in
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
            let response = try await client.setEmails(session: session, accountId: accountId, update: updates)
            let idSet = Set(messageIDs)
            var removedFromFolders: [String: [String]] = [:]
            var movedHeaders: [MessageHeader] = []
            lock.withLock {
                if let newState = response.newState { emailState = newState }
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
            let response = try await client.setEmails(session: session, accountId: accountId, update: updates)
            lock.withLock {
                if let newState = response.newState { emailState = newState }
            }
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
            let response = try await client.setEmails(
                session: session,
                accountId: accountId,
                destroy: messageIDs
            )
            let idSet = Set(messageIDs)
            var removedFromFolders: [String: [String]] = [:]
            lock.withLock {
                if let newState = response.newState { emailState = newState }
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
            let destroyIDs: [String]? = if let existingRemoteID = draft.remoteID, !existingRemoteID.isEmpty {
                [existingRemoteID]
            } else {
                nil
            }
            let setResult = try await client.setEmails(
                session: session,
                accountId: accountId,
                create: ["draft": emailObject],
                destroy: destroyIDs
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
                if let newState = setResult.newState { emailState = newState }
                if let oldRemote = draft.remoteID {
                    stagedDraftsByRemoteID.removeValue(forKey: oldRemote)
                }
                stagedDraftsByRemoteID[createdID] = updatedDraft
            }
            broadcast(.folderRefreshed(folderID: draftsMailbox.id))
            return updatedDraft
        } catch let error as JMAPError {
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Returns a locally staged copy of a draft saved during this session, if available.
    public func draft(for messageID: String) async throws -> Draft? {
        lock.withLock { stagedDraftsByRemoteID[messageID] }
    }

    /// Destroys a remote JMAP draft and clears any staged attachments.
    public func discard(draftID: String) async throws {
        let (session, accountId) = try requireConnectedSession()
        let remoteID: String = lock.withLock {
            let matching = stagedDraftsByRemoteID.first(where: { $0.value.id == draftID })
            let resolved = matching?.key ?? draftID
            stagedDraftsByRemoteID.removeValue(forKey: resolved)
            stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != draftID }
            return resolved
        }
        do {
            let result = try await client.setEmails(
                session: session,
                accountId: accountId,
                destroy: [remoteID]
            )
            lock.withLock {
                if let newState = result.newState { emailState = newState }
            }
        } catch let error as JMAPError {
            if case .notFound = error { return }
            recordSyncFailure(error)
            throw error.asMailBackendError()
        }
    }

    /// Sends a draft using `Identity/get` + batched `Email/set` + `EmailSubmission/set`, moving the sent copy to Sent.
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

            let (emailSet, _) = try await client.createAndSubmitEmail(
                session: session,
                accountId: accountId,
                creationID: "draft",
                emailObject: emailObject,
                destroyPreviousDraftID: draft.remoteID,
                identityId: identity.id,
                mailFrom: identity.email,
                rcptTo: allRecipients,
                onSuccessUpdateEmail: onSuccessPatch
            )
            let sentMessageID = emailSet.created?["draft"]?["id"]?.stringValue
            lock.withLock {
                if let newState = emailSet.newState { emailState = newState }
                if let oldRemote = draft.remoteID {
                    stagedDraftsByRemoteID.removeValue(forKey: oldRemote)
                }
                stagedAttachmentsByID = stagedAttachmentsByID.filter { $0.value.draftID != draft.id }
            }
            broadcast(.folderRefreshed(folderID: targetSentMailbox.id))
            return SendResult(sentMessageID: sentMessageID)
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
        do {
            let (queryResponse, getResponse) = try await client.queryAndGetEmails(
                session: session,
                accountId: accountId,
                filter: filter,
                position: 0,
                limit: Self.pageSize
            )
            let byID = Dictionary(uniqueKeysWithValues: getResponse.list.map { ($0.id, $0) })
            let fallbackFolderID = query.folderID ?? lock.withLock {
                mailboxesByID.values.first(where: { $0.folderRole == .inbox })?.id
            } ?? ""
            return queryResponse.ids.compactMap { id -> MessageHeader? in
                guard let email = byID[id] else { return nil }
                let folderID = query.folderID
                    ?? email.mailboxIds.first(where: { $0.value })?.key
                    ?? fallbackFolderID
                return email.toMessageHeader(folderID: folderID)
            }
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
                if !get.state.isEmpty { emailState = get.state }
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

        // 1. Mailbox delta sync.
        if let priorMailboxState, !priorMailboxState.isEmpty {
            do {
                let mbChanges = try await client.mailboxChanges(
                    session: session,
                    accountId: accountId,
                    sinceState: priorMailboxState
                )
                let changedMailboxIDs = mbChanges.created + mbChanges.updated
                if !changedMailboxIDs.isEmpty {
                    let fetched = try await client.getMailboxes(
                        session: session,
                        accountId: accountId,
                        ids: changedMailboxIDs
                    )
                    lock.withLock {
                        for mailbox in fetched.list {
                            mailboxesByID[mailbox.id] = mailbox
                        }
                    }
                }
                lock.withLock {
                    for destroyedID in mbChanges.destroyed {
                        mailboxesByID.removeValue(forKey: destroyedID)
                        headersByFolderID.removeValue(forKey: destroyedID)
                    }
                    mailboxState = mbChanges.newState
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
        if let priorEmailState, !priorEmailState.isEmpty {
            do {
                let changes = try await client.emailChanges(
                    session: session,
                    accountId: accountId,
                    sinceState: priorEmailState
                )
                try await applyEmailChanges(changes, session: session, accountId: accountId)
            } catch JMAPError.cannotCalculateChanges {
                fellBackToFull = true
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
        var fetchedEmails: [JMAPEmail] = []
        if !fetchIDs.isEmpty {
            let getResponse = try await client.getEmails(
                session: session,
                accountId: accountId,
                ids: fetchIDs,
                properties: JMAPClient.headerProperties
            )
            fetchedEmails = getResponse.list
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
            var consecutiveFailures = 0
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
                    consecutiveFailures = 0
                    for try await event in stream {
                        if Task.isCancelled { break }
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
                } catch is CancellationError {
                    break
                } catch JMAPError.authenticationRequired {
                    recordSyncFailure(.authenticationRequired)
                    break
                } catch {
                    consecutiveFailures += 1
                    let delay = eventSourceRetryDelay(consecutiveFailures)
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
        newState: String?,
        mutate: (inout MessageHeader) -> Void
    ) -> [String] {
        lock.withLock {
            if let newState { emailState = newState }
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
