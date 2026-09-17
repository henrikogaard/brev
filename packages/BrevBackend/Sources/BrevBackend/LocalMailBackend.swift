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

/// The "On My Mac" / "On My iPhone" backend: durable local folders backed by
/// a Maildir store outside every cache root (ADR-0077).
///
/// Mail arrives only through user actions — `copy`/`move` from a server
/// account and `importMessages` — never through a network connection. The
/// backend advertises only folder create/rename/delete so capability-driven
/// UI hides send, snooze, server rules, and sync-health rows for it. Headers
/// are indexed into the shared local search index under the local account ID;
/// the Maildir is the authority and the index is rebuilt from files whenever
/// it is missing or stale.
public final class LocalMailBackend: MailBackend, MailImporting, @unchecked Sendable {
    /// Account ID shared by every local backend instance on this device.
    public static let accountID = "local"
    /// `backendIdentifier` for the synthetic local account.
    public static let backendIdentifier = "local"

    private static let pageSize = 200

    public let account: BrevAccount
    public let capabilities: BackendCapabilities = [.folderCreate, .folderRename, .folderDelete]
    /// `.localAttachmentIndex` only when a search index is wired to persist
    /// extracted text (ADR-0078 §8); sources are already on-device.
    public let extendedCapabilities: BackendExtendedCapabilities

    /// The Maildir store backing this backend (exposed for backup/restore and
    /// Mail Storage sizing).
    public let store: LocalMaildirStore
    private let localSearchIndex: (any MailLocalSearchIndex)?
    private let bodyParser = IMAPMessageBodyParser()
    private let attachmentIndexConsent: AttachmentIndexConsentStore?
    /// Cache-only attachment indexer; nil when no index/consent store is wired.
    private(set) var attachmentIndexer: AttachmentIndexer?
    private var attachmentConsentObserver: NSObjectProtocol?

    private let stateLock = NSLock()
    private var eventContinuation: AsyncStream<MailEvent>.Continuation?
    private var cachedHasFolders: Bool

    /// `true` once at least one local folder exists. Kept synchronous so
    /// `AppSession.visibleBackends` can hide the account until the first
    /// folder is created; updated by folder mutations and `connect()`.
    public var hasFolders: Bool {
        stateLock.withLock { cachedHasFolders }
    }

    /// - Parameters:
    ///   - store: The Maildir store; inject a temp root in tests.
    ///   - localSearchIndex: The shared local index for search; when nil,
    ///     `search` falls back to an in-memory header scan.
    ///   - account: Override for tests; defaults to the synthetic
    ///     "On My Mac"/"On My iPhone" account.
    public init(
        store: LocalMaildirStore = LocalMaildirStore(),
        localSearchIndex: (any MailLocalSearchIndex)? = nil,
        account: BrevAccount? = nil,
        attachmentIndexConsent: AttachmentIndexConsentStore? = nil
    ) {
        self.store = store
        self.localSearchIndex = localSearchIndex
        self.attachmentIndexConsent = attachmentIndexConsent
        self.account = account ?? BrevAccount(
            id: Self.accountID,
            displayName: Self.deviceAccountDisplayName,
            emailAddress: "",
            backendIdentifier: Self.backendIdentifier,
            backendDisplayName: Self.deviceAccountDisplayName
        )
        // The manifest is a tiny JSON file; reading it synchronously here
        // keeps `hasFolders` honest before the first async call.
        let manifestURL = store.rootURL.appendingPathComponent("folders.json")
        let count = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode([LocalMaildirStore.FolderRecord].self, from: $0) }?
            .count ?? 0
        cachedHasFolders = count > 0
        var extended: BackendExtendedCapabilities = [
            .clientSideThreading, .messageCopy, .rawMessageSource, .rawMessageBytes,
        ]
        if localSearchIndex != nil {
            extended.insert(.localAttachmentIndex)
        }
        extendedCapabilities = extended
        if let localSearchIndex {
            let store = store
            let parser = bodyParser
            let accountID = self.account.id
            attachmentIndexer = AttachmentIndexer(
                accountID: accountID,
                isEnabled: { attachmentIndexConsent?.isEnabled(accountID: accountID) ?? false },
                index: localSearchIndex,
                sweepEntries: {
                    var entries: [AttachmentIndexer.SweepEntry] = []
                    for record in await (try? store.folders()) ?? [] {
                        for stored in await (try? store.enumerate(folderID: record.id)) ?? [] {
                            entries.append(.init(
                                messageID: Self.messageID(for: stored.ref),
                                folderID: record.id
                            ))
                        }
                    }
                    return entries
                },
                rawMessageProvider: { messageID in
                    guard let separator = messageID.firstIndex(of: ":") else { return nil }
                    let ref = LocalMaildirStore.LocalMessageRef(
                        folderID: String(messageID[..<separator]),
                        uniqueID: String(messageID[messageID.index(after: separator)...])
                    )
                    guard let data = try? await store.data(for: ref) else { return nil }
                    return parser.rawMessageString(from: data)
                }
            )
        }
        if let attachmentIndexConsent {
            attachmentConsentObserver = NotificationCenter.default.addObserver(
                forName: AttachmentIndexConsentStore.didChangeNotification,
                object: attachmentIndexConsent,
                queue: nil
            ) { [weak self] note in
                guard (note.userInfo?["accountID"] as? String) == self?.account.id else { return }
                Task { [weak self] in
                    await self?.attachmentIndexingConsentChanged()
                }
            }
        }
    }

    private static var deviceAccountDisplayName: String {
        #if os(macOS)
        String(localized: "On My Mac", bundle: .module)
        #else
        String(localized: "On My iPhone", bundle: .module)
        #endif
    }

    // MARK: - Connection lifecycle

    /// Connects: ensures the store root exists and rebuilds the search index
    /// for any folder whose Maildir has files the index does not know about
    /// (ADR-0077 decision 2 — the files are the authority).
    public func connect() async throws {
        for record in try await store.folders() {
            let stored = try await store.enumerate(folderID: record.id)
            guard let localSearchIndex, !stored.isEmpty else { continue }
            let indexed = await localSearchIndex.cachedHeaders(
                for: folderModel(for: record),
                account: account,
                pageToken: nil
            )
            if indexed == nil || (indexed?.headers.count ?? 0) < stored.count {
                await localSearchIndex.storeHeaders(
                    stored.map { Self.header(from: $0) },
                    account: account
                )
            }
        }
        await refreshFolderPresence()
        // Local sources are always present, so the sweep is the indexing
        // trigger (ADR-0078 §2); it is a no-op unless the account opted in.
        await attachmentIndexer?.sweep()
    }

    /// Re-applies the consent boundary: enabling sweeps; disabling stops work
    /// and removes every indexed row for the local account.
    func attachmentIndexingConsentChanged() async {
        guard let attachmentIndexConsent else { return }
        if attachmentIndexConsent.isEnabled(accountID: account.id) {
            await attachmentIndexer?.sweep()
        } else {
            await attachmentIndexer?.disable()
        }
    }

    public func disconnect() async {
        await attachmentIndexer?.stop()
    }

    public func flushLocalCaches() async {
        await attachmentIndexer?.stop()
    }

    public func replayOfflineMutations() async {}

    public func subscribeToChanges() -> AsyncStream<MailEvent> {
        AsyncStream { continuation in
            stateLock.withLock {
                eventContinuation = continuation
            }
        }
    }

    public func extensionService<Service>(_ type: Service.Type) -> Service? {
        self as? Service
    }

    // MARK: - Folders

    public func folders() async throws -> [Folder] {
        var models: [Folder] = []
        for record in try await store.folders() {
            let stored = await (try? store.enumerate(folderID: record.id)) ?? []
            let unread = stored.filter { !$0.flags.contains(.seen) }.count
            models.append(Folder(
                id: record.id,
                name: record.name,
                role: .custom,
                parentID: record.parentID,
                unreadCount: unread,
                totalCount: stored.count
            ))
        }
        return models
    }

    public func refresh(folder: Folder) async throws {
        emit(.folderRefreshed(folderID: folder.id))
    }

    public func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder {
        let record = try await store.createFolder(name: name, parentID: parentID)
        await refreshFolderPresence()
        let folder = folderModel(for: record)
        emit(.folderRefreshed(folderID: folder.id))
        return folder
    }

    public func renameFolder(id: Folder.ID, name: String) async throws -> Folder {
        do {
            let record = try await store.renameFolder(id: id, name: name)
            emit(.folderRefreshed(folderID: id))
            return folderModel(for: record)
        } catch let error as LocalMaildirStore.StoreError {
            throw mapStoreError(error)
        }
    }

    /// Permanently deletes a local folder and every message file in it.
    /// There is no Trash — the caller confirms before calling.
    public func deleteFolder(id: Folder.ID) async throws {
        do {
            try await store.deleteFolder(id: id)
        } catch let error as LocalMaildirStore.StoreError {
            throw mapStoreError(error)
        }
        await localSearchIndex?.clearFolder(folderID: id, account: account)
        await refreshFolderPresence()
        emit(.folderRefreshed(folderID: id))
    }

    public func flushFolder(id: Folder.ID) async throws {
        _ = id
        throw MailBackendError.notSupported(.folderFlush)
    }

    // MARK: - Messages

    public func messages(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        let headers = try await sortedHeaders(in: folder.id)
        let offset = pageToken.flatMap(Int.init) ?? 0
        guard offset < headers.count else { return ([], nil) }
        let end = Swift.min(offset + Self.pageSize, headers.count)
        let next = end < headers.count ? String(end) : nil
        return (Array(headers[offset ..< end]), next)
    }

    public func enumerateMessages(
        in folder: Folder,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        try await messages(in: folder, pageToken: pageToken)
    }

    public func body(for messageID: String) async throws -> MessageBody {
        let data = try await rawMessageData(for: messageID)
        return bodyParser.parse(
            messageID: messageID,
            rawMessage: bodyParser.rawMessageString(from: data)
        )
    }

    public func rawSource(for messageID: String) async throws -> String {
        try await bodyParser.rawMessageString(from: rawMessageData(for: messageID))
    }

    public func rawMessageData(for messageID: String) async throws -> Data {
        try await store.data(for: ref(for: messageID))
    }

    public func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        try await updateFlags(for: messageIDs) { flags in
            if isRead { flags.insert(.seen) } else { flags.remove(.seen) }
        }
    }

    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        try await updateFlags(for: messageIDs) { flags in
            if isFlagged { flags.insert(.flagged) } else { flags.remove(.flagged) }
        }
    }

    /// Permanent delete — local folders have no Trash, so the caller
    /// confirms first. Removes the file and the index rows.
    public func delete(messageIDs: [String]) async throws {
        var refs: [LocalMaildirStore.LocalMessageRef] = []
        for id in messageIDs {
            try await refs.append(ref(for: id))
        }
        for ref in refs {
            try await store.remove(ref)
        }
        await localSearchIndex?.deleteMessages(messageIDs, account: account)
        for ref in refs {
            emit(.messagesRemoved(folderID: ref.folderID, messageIDs: [Self.messageID(for: ref)]))
        }
    }

    /// Moves messages between local folders: appends to the destination and
    /// removes the source file only after the write succeeded.
    public func move(messageIDs: [String], to folder: Folder) async throws {
        for id in messageIDs {
            let ref = try await ref(for: id)
            let data = try await store.data(for: ref)
            let flags = try await store.flags(for: ref)
            _ = try await store.append(rawMessage: data, flags: flags, folderID: folder.id)
            try await store.remove(ref)
            await reindex(messageID: id, from: ref.folderID, to: folder.id)
        }
        emit(.folderRefreshed(folderID: folder.id))
    }

    /// Copies messages between local folders without touching the source.
    public func copy(messageIDs: [String], to folder: Folder) async throws {
        for id in messageIDs {
            let ref = try await ref(for: id)
            let data = try await store.data(for: ref)
            let flags = try await store.flags(for: ref)
            _ = try await store.append(rawMessage: data, flags: flags, folderID: folder.id)
        }
        if let index = localSearchIndex {
            let headers = try await sortedHeaders(in: folder.id)
            await index.storeHeaders(headers, account: account)
        }
        emit(.folderRefreshed(folderID: folder.id))
    }

    /// Every message ID currently stored in a folder — used by restore Merge
    /// to dedupe by Message-ID.
    public func storedRFCMessageIDs(in folderID: Folder.ID) async throws -> Set<String> {
        let stored = try await store.enumerate(folderID: folderID)
        return Set(stored.compactMap { Self.header(from: $0).messageID })
    }

    /// Total on-disk size of the durable local folders (ADR-0077 decision 6 —
    /// not a cache; used by Settings → Mail Storage and the backup preview).
    public func size() async throws -> Int64 {
        await store.size()
    }

    // MARK: - MailImporting

    /// Imports parsed messages into a local folder. This is the single write
    /// path Copy/Move/Import/backup-restore all funnel through: each message
    /// is re-serialized to RFC 5322, fsynced, and indexed.
    public func importMessages(
        _ messages: [ImportedMessage],
        into folder: Folder
    ) async throws -> MailImportSummary {
        var errors: [String] = []
        var importedCount = 0
        var importedIDs: [String] = []
        for (index, message) in messages.enumerated() {
            let raw = Self.rawData(from: message)
            guard !raw.isEmpty else {
                errors.append("Message \(index + 1) could not be imported.")
                continue
            }
            let ref = try await store.append(
                rawMessage: raw,
                flags: [.seen],
                folderID: folder.id
            )
            importedIDs.append(Self.messageID(for: ref))
            importedCount += 1
        }
        if let index = localSearchIndex, importedCount > 0 {
            let headers = try await sortedHeaders(in: folder.id)
            await index.storeHeaders(headers, account: account)
        }
        if !importedIDs.isEmpty {
            emit(.messagesAdded(folderID: folder.id, messageIDs: importedIDs))
        }
        return MailImportSummary(importedCount: importedCount, errors: errors)
    }

    /// Imports exact RFC 5322 bytes — the path Copy/Move uses so the stored
    /// file is byte-identical to the server's copy. Returns the new
    /// backend-wide message ID.
    @discardableResult
    public func importRaw(
        _ data: Data,
        into folder: Folder,
        flags: Set<MaildirFlag> = [.seen]
    ) async throws -> MessageHeader.ID {
        let ref = try await store.append(rawMessage: data, flags: flags, folderID: folder.id)
        let id = Self.messageID(for: ref)
        if let index = localSearchIndex,
           let data2 = try? await store.data(for: ref) {
            await index.storeHeaders(
                [Self.header(from: LocalMaildirStore.StoredMessage(
                    ref: ref, flags: flags, data: data2
                ))],
                account: account
            )
        }
        await attachmentIndexer?.noteSourceCached(messageID: id, folderID: folder.id)
        emit(.messagesAdded(folderID: folder.id, messageIDs: [id]))
        return id
    }

    // MARK: - Drafts / sending — no server, so nothing to send with

    public func save(draft: Draft) async throws -> Draft {
        _ = draft
        throw MailBackendError.notSupported(capabilities)
    }

    public func discard(draftID: String) async throws {
        _ = draftID
        throw MailBackendError.notSupported(capabilities)
    }

    public func send(draft: Draft) async throws -> SendResult {
        _ = draft
        throw MailBackendError.notSupported(capabilities)
    }

    // MARK: - Calendar — no server-side invite handling locally

    public func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        _ = attachmentID
        throw MailBackendError.notSupported(capabilities)
    }

    public func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
        _ = messageID
        _ = response
        throw MailBackendError.notSupported(capabilities)
    }

    // MARK: - Search

    /// Local attachment-content matches for search results (ADR-0078 §5).
    public func matchedAttachmentNames(
        matching query: SearchQuery,
        account: BrevAccount,
        messageIDs: [MessageHeader.ID]
    ) async -> [MessageHeader.ID: String] {
        await localSearchIndex?.matchedAttachmentNames(
            matching: query, account: account, messageIDs: messageIDs
        ) ?? [:]
    }

    /// Size of the local account's attachment-content index (ADR-0078).
    public func attachmentIndexBytes() async -> Int {
        await localSearchIndex?.attachmentIndexBytes(accountID: account.id) ?? 0
    }

    /// Clears the attachment index and re-sweeps stored local folders.
    public func rebuildAttachmentIndex() async {
        await attachmentIndexer?.rebuild()
    }

    /// Removes every indexed attachment row and stops indexing work.
    public func removeAttachmentIndex() async {
        await attachmentIndexer?.disable()
    }

    /// Searches the shared local index under the local account ID; falls back
    /// to an in-memory header scan when no index is wired (tests, previews).
    public func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        if let localSearchIndex {
            return await localSearchIndex.search(query, account: account)
        }
        var all: [MessageHeader] = []
        for record in try await store.folders() {
            all += try await sortedHeaders(in: record.id)
        }
        return all.filter { query.matches($0) }
    }

    // MARK: - Helpers

    /// The backend-wide message ID for a stored message:
    /// `"<folderID>:<maildir-unique>"`.
    public static func messageID(for ref: LocalMaildirStore.LocalMessageRef) -> MessageHeader.ID {
        "\(ref.folderID):\(ref.uniqueID)"
    }

    private func ref(for messageID: String) async throws -> LocalMaildirStore.LocalMessageRef {
        guard let separator = messageID.firstIndex(of: ":") else {
            throw MailBackendError.notFound(id: messageID)
        }
        let folderID = String(messageID[..<separator])
        let uniqueID = String(messageID[messageID.index(after: separator)...])
        guard !uniqueID.isEmpty else {
            throw MailBackendError.notFound(id: messageID)
        }
        return LocalMaildirStore.LocalMessageRef(folderID: folderID, uniqueID: uniqueID)
    }

    private func folderModel(for record: LocalMaildirStore.FolderRecord) -> Folder {
        Folder(id: record.id, name: record.name, role: .custom, parentID: record.parentID)
    }

    private func sortedHeaders(in folderID: Folder.ID) async throws -> [MessageHeader] {
        let stored = try await store.enumerate(folderID: folderID)
        return stored.map { Self.header(from: $0) }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }

    /// Builds a `MessageHeader` from a stored message's raw bytes and flags.
    static func header(from stored: LocalMaildirStore.StoredMessage) -> MessageHeader {
        let result = EMLReader().read(data: stored.data)
        let imported = result.messages.first
        let id = messageID(for: stored.ref)
        let flags = stored.flags
        let rfcMessageID = imported?.messageID
        let inReplyTo = imported?.header("In-Reply-To")
        let subject = imported?.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText = String(data: imported?.bodyData ?? Data(), encoding: .utf8)
            ?? String(data: imported?.bodyData ?? Data(), encoding: .isoLatin1)
            ?? ""
        return MessageHeader(
            id: id,
            threadID: inReplyTo ?? rfcMessageID ?? id,
            folderID: stored.ref.folderID,
            from: parseCorrespondent(imported?.from) ?? Correspondent(email: "unknown@example.invalid"),
            replyTo: parseCorrespondents(imported?.header("Reply-To")),
            to: parseCorrespondents(imported?.header("To")),
            cc: parseCorrespondents(imported?.header("Cc")),
            bcc: [],
            subject: (subject?.isEmpty == false ? subject : nil) ?? "(No subject)",
            snippet: String(bodyText.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
            date: parseHeaderDate(imported?.date) ?? Date.distantPast,
            isRead: flags.contains(.seen),
            isFlagged: flags.contains(.flagged),
            isAnswered: flags.contains(.replied),
            isForwarded: flags.contains(.passed),
            hasAttachments: imported?.header("Content-Type")?
                .localizedCaseInsensitiveContains("multipart/mixed") == true
                || imported?.header("Content-Disposition")?
                .localizedCaseInsensitiveContains("attachment") == true,
            messageID: rfcMessageID,
            inReplyTo: inReplyTo
        )
    }

    /// Re-serializes an `ImportedMessage` into RFC 5322 bytes.
    static func rawData(from message: ImportedMessage) -> Data {
        var head = message.headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\r\n")
        if !head.isEmpty {
            head += "\r\n"
        }
        var data = Data((head + "\r\n").utf8)
        data.append(message.bodyData)
        return data
    }

    private func updateFlags(
        for messageIDs: [String],
        mutate: (inout Set<MaildirFlag>) -> Void
    ) async throws {
        var touched: [(ref: LocalMaildirStore.LocalMessageRef, id: String)] = []
        for id in messageIDs {
            let ref = try await ref(for: id)
            var flags = try await store.flags(for: ref)
            mutate(&flags)
            try await store.setFlags(flags, for: ref)
            touched.append((ref, id))
        }
        if let index = localSearchIndex {
            for (_, id) in touched {
                await index.deleteMessages([id], account: account)
            }
            var byFolder: [String: [LocalMaildirStore.LocalMessageRef]] = [:]
            for (ref, _) in touched {
                byFolder[ref.folderID, default: []].append(ref)
            }
            for (folderID, refs) in byFolder {
                var headers: [MessageHeader] = []
                for ref in refs {
                    guard let data = try? await store.data(for: ref) else { continue }
                    let flags = await (try? store.flags(for: ref)) ?? []
                    headers.append(Self.header(from: LocalMaildirStore.StoredMessage(
                        ref: ref, flags: flags, data: data
                    )))
                }
                await index.storeHeaders(headers, account: account)
                emit(.messagesUpdated(folderID: folderID, messageIDs: headers.map(\.id)))
            }
        } else {
            var byFolder: [String: [String]] = [:]
            for (ref, id) in touched {
                byFolder[ref.folderID, default: []].append(id)
            }
            for (folderID, ids) in byFolder {
                emit(.messagesUpdated(folderID: folderID, messageIDs: ids))
            }
        }
    }

    private func reindex(messageID: String, from sourceFolderID: String, to folderID: String) async {
        guard let index = localSearchIndex else { return }
        await index.deleteMessages([messageID], account: account)
        if let headers = try? await sortedHeaders(in: folderID) {
            await index.storeHeaders(headers, account: account)
        }
        _ = sourceFolderID
    }

    private func refreshFolderPresence() async {
        let has = await ((try? store.folders()) ?? []).isEmpty == false
        stateLock.withLock { cachedHasFolders = has }
    }

    private func emit(_ event: MailEvent) {
        _ = stateLock.withLock { eventContinuation?.yield(event) }
    }

    private func mapStoreError(_ error: LocalMaildirStore.StoreError) -> MailBackendError {
        switch error {
        case .folderNotFound(let id), .messageNotFound(let id):
            return .notFound(id: id)
        case .duplicateFolderName(let name):
            return .backendSpecific(message: String(
                localized: "A local folder named “\(name)” already exists.", bundle: .module
            ))
        case .emptyFolderName:
            return .backendSpecific(message: String(
                localized: "Local folder names can't be empty.", bundle: .module
            ))
        }
    }

    private static func parseCorrespondents(_ raw: String?) -> [Correspondent] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { parseCorrespondent(String($0)) }
    }

    private static func parseCorrespondent(_ raw: String?) -> Correspondent? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if let open = trimmed.lastIndex(of: "<"),
           let close = trimmed.lastIndex(of: ">"),
           open < close {
            let name = trimmed[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            let email = trimmed[trimmed.index(after: open) ..< close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard email.contains("@") else { return nil }
            return Correspondent(name: name.isEmpty ? nil : name, email: email)
        }
        let email = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        guard email.contains("@") else { return nil }
        return Correspondent(email: email)
    }

    private static func parseHeaderDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        for formatter in headerDateFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let headerDateFormatters: [DateFormatter] = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
