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

/// A fixture `MailBackend` used by SwiftUI previews, tests, and the app's debug demo and isolated modes.
///
/// State is held in an internal actor so concurrent calls from multiple
/// tasks behave sanely. Canned data is seeded at construction; mutating
/// operations update the in-memory state and emit `MailEvent`s on the
/// stream returned by `subscribeToChanges()`.
public final class MockBackend: MailBackend, AutoReplyManaging, ServerRuleManaging, ContactLookupProviding, MailImporting,
    SyncHealthReporting, SyncHealthRepairing, SyncConflictManaging,
    CachedConversationProviding, RelatedConversationLoading, LocalDraftAttachmentProviding, CachedListUnsubscribeProviding,
    ScheduledSendManaging, ScheduledSendEditing, @unchecked Sendable {
    public let account: BrevAccount
    public let capabilities: BackendCapabilities
    public let extendedCapabilities: BackendExtendedCapabilities

    /// Test/preview hook for cached conversation lookup; nil reports not supported.
    public var cachedConversationHandler:
        (@Sendable (ConversationMember, Bool) async throws -> ConversationSnapshot)?
    /// Test/preview hook for suspending or failing cache-only header reads.
    public var cachedMessageHeadersHandler:
        (@Sendable (Folder, MailSourceID) async throws -> [MessageHeader])?
    /// Test/preview hook for consented remote related-header loading.
    public var relatedConversationHandler:
        (@Sendable (ConversationMember, Bool, String?,
                    @escaping @Sendable (ConversationSnapshot) async -> Void) async throws -> ConversationSnapshot)?
    var sendHandler: (@Sendable (Draft, MailSourceID?) async throws -> SendResult)?

    private let store: Store
    private let contacts: [ContactLookupResult]
    private let supportsScheduledSend: Bool
    private let scheduledSendSnapshot: MockScheduledSendSnapshot

    /// Creates a preview or demo backend; scheduled-send fixtures persist only when a directory is supplied.
    /// - Parameters:
    ///   - supportsScheduledSend: Whether the backend exposes scheduled-send services.
    ///   - persistenceDirectory: Optional private, file-backed Mock fixture storage.
    ///   - now: Synchronous clock used for due checks and Sent timestamps.
    ///   - automaticDeliveryEnabled: Disables the worker for deterministic tests while keeping explicit delivery available.
    public init(
        account: BrevAccount = .preview,
        capabilities: BackendCapabilities = .full,
        extendedCapabilities: BackendExtendedCapabilities = [],
        folders: [Folder] = MockBackend.previewFolders,
        messagesByFolder: [String: [MessageHeader]] = MockBackend.previewMessages,
        mailboxes: [Mailbox]? = nil,
        contacts: [ContactLookupResult]? = nil,
        supportsScheduledSend: Bool = true,
        persistenceDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        automaticDeliveryEnabled: Bool = true
    ) {
        self.account = account
        self.capabilities = capabilities
        self.extendedCapabilities = extendedCapabilities
        self.supportsScheduledSend = supportsScheduledSend
        let journal = persistenceDirectory.map { MockSendJournal(directoryURL: $0, accountID: account.id) }
        let scheduledSendSnapshot = MockScheduledSendSnapshot()
        self.scheduledSendSnapshot = scheduledSendSnapshot
        let resolvedMailboxes: [Mailbox]
        if let mailboxes, !mailboxes.isEmpty {
            resolvedMailboxes = mailboxes
        } else {
            resolvedMailboxes = Self.previewMailboxes(for: account)
        }
        self.contacts = contacts ?? Self.previewContacts(
            accountID: account.id,
            mailboxID: resolvedMailboxes.first?.id ?? account.id
        )
        let store = Store(
            mailboxes: resolvedMailboxes,
            dataByMailboxID: Self.previewMailboxData(
                mailboxes: resolvedMailboxes,
                primaryFolders: folders,
                primaryMessagesByFolder: messagesByFolder
            ),
            accountID: account.id,
            journal: journal,
            now: now,
            automaticDeliveryEnabled: automaticDeliveryEnabled,
            scheduledSendSnapshot: scheduledSendSnapshot
        )
        self.store = store
        Task { [weak store] in
            await store?.startWorkerIfNeeded()
        }
    }

    /// The set of email addresses that have been blocked via `blockSender(email:)`.
    /// Exposed for testing; not part of the `MailBackend` protocol.
    public var blockedSenders: Set<String> {
        get async { await store.blockedSenders }
    }

    /// Seeds a replay conflict into the given mailbox. Useful in tests and
    /// previews that exercise the conflict review UI.
    public func seedConflict(_ conflict: ReplayConflict, mailboxID: Mailbox.ID) async throws {
        try await store.seedConflict(conflict, mailboxID: mailboxID)
    }

    public func connect() async throws {
        try await store.resume()
    }

    public func disconnect() async {
        await store.pause()
    }

    public func folders() async throws -> [Folder] {
        try await store.folderSnapshots()
    }

    public func mailboxes() async throws -> [Mailbox] {
        await store.mailboxSnapshots()
    }

    public func currentMailbox() async throws -> Mailbox {
        try await store.currentMailbox()
    }

    public func switchMailbox(id: String) async throws {
        try await store.switchMailbox(id: id)
    }

    public func folders(in sourceID: MailSourceID) async throws -> [Folder] {
        try await store.folderSnapshots(mailboxID: mailboxID(for: sourceID))
    }

    public func refresh(folder: Folder, in sourceID: MailSourceID) async throws {
        _ = try await mailboxID(for: sourceID)
        await store.emit(.folderRefreshed(folderID: folder.id))
    }

    public func refresh(folder: Folder) async throws {
        await store.emit(.folderRefreshed(folderID: folder.id))
    }

    public func createFolder(name: String, parentID: Folder.ID?) async throws -> Folder {
        guard capabilities.contains(.folderCreate) else {
            throw MailBackendError.notSupported(.folderCreate)
        }
        return await store.createFolder(name: name, parentID: parentID)
    }

    public func createFolder(
        name: String,
        parentID: Folder.ID?,
        sourceID: MailSourceID
    ) async throws -> Folder {
        guard capabilities.contains(.folderCreate) else {
            throw MailBackendError.notSupported(.folderCreate)
        }
        return try await store.createFolder(
            name: name,
            parentID: parentID,
            mailboxID: mailboxID(for: sourceID)
        )
    }

    public func renameFolder(id: Folder.ID, name: String) async throws -> Folder {
        guard capabilities.contains(.folderRename) else {
            throw MailBackendError.notSupported(.folderRename)
        }
        return try await store.renameFolder(id: id, name: name)
    }

    public func renameFolder(
        id: Folder.ID,
        name: String,
        sourceID: MailSourceID
    ) async throws -> Folder {
        guard capabilities.contains(.folderRename) else {
            throw MailBackendError.notSupported(.folderRename)
        }
        return try await store.renameFolder(
            id: id,
            name: name,
            mailboxID: mailboxID(for: sourceID)
        )
    }

    public func deleteFolder(id: Folder.ID) async throws {
        guard capabilities.contains(.folderDelete) else {
            throw MailBackendError.notSupported(.folderDelete)
        }
        try await store.deleteFolder(id: id)
    }

    public func deleteFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        guard capabilities.contains(.folderDelete) else {
            throw MailBackendError.notSupported(.folderDelete)
        }
        try await store.deleteFolder(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func flushFolder(id: Folder.ID) async throws {
        guard capabilities.contains(.folderFlush) else {
            throw MailBackendError.notSupported(.folderFlush)
        }
        try await store.flushFolder(id: id)
    }

    public func flushFolder(id: Folder.ID, sourceID: MailSourceID) async throws {
        guard capabilities.contains(.folderFlush) else {
            throw MailBackendError.notSupported(.folderFlush)
        }
        try await store.flushFolder(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func messages(in folder: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        let all = try await store.messages(in: folder.id)
        return (all, nil)
    }

    public func messages(
        in folder: Folder,
        sourceID: MailSourceID,
        pageToken: String?
    ) async throws -> (headers: [MessageHeader], nextPageToken: String?) {
        let all = try await store.messages(
            in: folder.id,
            mailboxID: mailboxID(for: sourceID)
        )
        return (all, nil)
    }

    public func body(for messageID: String) async throws -> MessageBody {
        await store.body(for: messageID)
    }

    public func body(for messageID: String, sourceID: MailSourceID) async throws -> MessageBody {
        try await store.body(for: messageID, mailboxID: mailboxID(for: sourceID))
    }

    public func rawSource(for messageID: String) async throws -> String {
        await store.rawMessageSource(for: messageID)
    }

    public func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String {
        try await store.rawMessageSource(for: messageID, mailboxID: mailboxID(for: sourceID))
    }

    public func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        try await store.downloadAttachment(attachment)
    }

    public func downloadAttachment(_ attachment: Attachment, sourceID: MailSourceID) async throws -> Data {
        try await store.downloadAttachment(attachment, mailboxID: mailboxID(for: sourceID))
    }

    public func setRead(_ isRead: Bool, for messageIDs: [String]) async throws {
        await store.mutate(ids: messageIDs) { $0.isRead = isRead ? true : false }
    }

    public func setRead(_ isRead: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await store.mutate(ids: messageIDs, mailboxID: mailboxID(for: sourceID)) {
            $0.isRead = isRead
        }
    }

    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String]) async throws {
        await store.mutate(ids: messageIDs) { $0.isFlagged = isFlagged }
    }

    public func setFlagged(_ isFlagged: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await store.mutate(ids: messageIDs, mailboxID: mailboxID(for: sourceID)) {
            $0.isFlagged = isFlagged
        }
    }

    public func setFlagColor(_ color: FlagColor?, for messageIDs: [String]) async throws {
        await store.mutate(ids: messageIDs) {
            $0.flagColor = color
            $0.isFlagged = color != nil ? true : $0.isFlagged
        }
    }

    public func setFlagColor(_ color: FlagColor?, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await store.mutate(ids: messageIDs, mailboxID: mailboxID(for: sourceID)) {
            $0.flagColor = color
            $0.isFlagged = color != nil ? true : $0.isFlagged
        }
    }

    public func setJunk(_ isJunk: Bool, for messageIDs: [String]) async throws {
        // In the mock, junk == moving to/from the spam folder.
        guard capabilities.contains(.junkAPI) else {
            throw MailBackendError.notSupported(.junkAPI)
        }
        if isJunk {
            if let spam = await store.spamFolderID() {
                await store.move(ids: messageIDs, to: spam)
            }
        } else {
            let inboxID = await store.inboxFolderID()
            await store.move(ids: messageIDs, to: inboxID)
        }
    }

    public func setJunk(_ isJunk: Bool, for messageIDs: [String], sourceID: MailSourceID) async throws {
        try await setJunk(isJunk, for: messageIDs)
    }

    public func blockSender(email: String) async throws {
        guard capabilities.contains(.blockSender) else {
            throw MailBackendError.notSupported(.blockSender)
        }
        await store.addBlockedSender(email)
    }

    public func blockSender(email: String, sourceID: MailSourceID) async throws {
        try await blockSender(email: email)
    }

    /// Moves preview messages with a reversal bound to their original mailbox.
    public func moveWithUndo(messageIDs: [MessageHeader.ID], from sourceFolder: Folder, to destination: Folder,
                             sourceID: MailSourceID) async throws -> MailMoveUndo? {
        guard sourceFolder.id != destination.id, !messageIDs.isEmpty else { return nil }
        try await move(messageIDs: messageIDs, to: destination, sourceID: sourceID)
        return MailMoveUndo(sourceID: sourceID, originalFolder: sourceFolder) { [self] in
            try await move(messageIDs: messageIDs, to: sourceFolder, sourceID: sourceID)
            return Dictionary(messageIDs.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func move(messageIDs: [String], to folder: Folder) async throws {
        await store.move(ids: messageIDs, to: folder.id)
    }

    public func move(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {
        try await store.move(ids: messageIDs, to: folder.id, mailboxID: mailboxID(for: sourceID))
    }

    public func copy(messageIDs: [String], to folder: Folder) async throws {
        await store.copy(ids: messageIDs, to: folder.id)
    }

    public func copy(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws {
        try await store.copy(ids: messageIDs, to: folder.id, mailboxID: mailboxID(for: sourceID))
    }

    public func delete(messageIDs: [String]) async throws {
        await store.delete(ids: messageIDs)
    }

    public func delete(messageIDs: [String], sourceID: MailSourceID) async throws {
        try await store.delete(ids: messageIDs, mailboxID: mailboxID(for: sourceID))
    }

    public func save(draft: Draft) async throws -> Draft {
        try await store.save(draft: draft)
    }

    public func save(draft: Draft, sourceID: MailSourceID) async throws -> Draft {
        try await store.save(draft: draft, mailboxID: mailboxID(for: sourceID))
    }

    /// Returns the canonical saved draft from the active mock mailbox.
    public func draft(for messageID: String) async throws -> Draft? {
        try await store.draft(for: messageID)
    }

    /// Returns a locally saved draft only from the requested source.
    public func draft(for messageID: String, sourceID: MailSourceID) async throws -> Draft? {
        try await store.draft(for: messageID, mailboxID: mailboxID(for: sourceID))
    }

    /// Reads complete locally staged bytes without a mock download operation.
    public func localDraftAttachments(for draft: Draft) async throws -> [MIMEMessageAttachment] {
        try await store.localDraftAttachments(for: draft)
    }

    /// Resolves staging IDs inside the owning mock account and mailbox.
    public func localDraftAttachments(for draft: Draft, sourceID: MailSourceID) async throws -> [MIMEMessageAttachment] {
        try await store.localDraftAttachments(for: draft, mailboxID: mailboxID(for: sourceID))
    }

    public func discard(draftID: String) async throws {
        try await store.discard(draftID: draftID)
    }

    public func discard(draftID: String, sourceID: MailSourceID) async throws {
        try await store.discard(draftID: draftID, mailboxID: mailboxID(for: sourceID))
    }

    public func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String {
        try await store.uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType
        )
    }

    public func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        sourceID: MailSourceID
    ) async throws -> String {
        try await store.uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType,
            mailboxID: mailboxID(for: sourceID)
        )
    }

    public func send(draft: Draft) async throws -> SendResult {
        try await store.ensureActive()
        if let sendHandler { return try await sendHandler(draft, nil) }
        if let scheduledFor = draft.scheduledFor {
            let mailbox = try await store.currentMailbox()
            let result = try await store.schedule(draft: draft, scheduledFor: scheduledFor, mailboxID: mailbox.id)
            await store.startWorkerIfNeeded(restart: true)
            return result
        }
        let messageID = try await store.send(draft: draft)
        return SendResult(sentMessageID: messageID)
    }

    public func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult {
        try await store.ensureActive()
        if let sendHandler { return try await sendHandler(draft, sourceID) }
        let owner = try mailboxID(for: sourceID)
        if let scheduledFor = draft.scheduledFor {
            let result = try await store.schedule(draft: draft, scheduledFor: scheduledFor, mailboxID: owner)
            await store.startWorkerIfNeeded(restart: true)
            return result
        }
        let messageID = try await store.send(draft: draft, mailboxID: owner)
        return SendResult(sentMessageID: messageID)
    }

    public func pendingScheduledSends() -> [PendingScheduledSend] {
        scheduledSendSnapshot.read()
    }

    public func scheduledDraft(id: String) async throws -> Draft {
        guard let draft = try await store.scheduledDraft(id: id) else { throw ScheduledSendEditingError.notFound }
        return draft
    }

    public func cancelScheduledSend(id: String) async throws -> Draft? {
        let draft = try await store.cancelScheduledSend(id: id)
        await store.startWorkerIfNeeded(restart: true)
        return draft
    }

    public func rescheduleSend(id: String, for date: Date) async throws {
        try await store.rescheduleSend(id: id, for: date)
        await store.startWorkerIfNeeded(restart: true)
    }

    /// Treats a reviewed Mock send as a new schedule at the supplied due date.
    public func retryReviewedScheduledSend(id: String, for date: Date) async throws {
        try await rescheduleSend(id: id, for: date)
    }

    public func deliverDueScheduledSends() async {
        await store.deliverDueScheduledSends()
        await store.startWorkerIfNeeded(restart: true)
    }

    /// Clears this Mock fixture's scheduled-send journal and its in-memory projections.
    public func purgePersistentState() async throws {
        try await store.purgePersistentState()
    }

    /// Returns every seeded header owned by the requested mailbox and folder.
    public func cachedMessageHeaders(in folder: Folder, sourceID: MailSourceID) async throws -> [MessageHeader] {
        if let cachedMessageHeadersHandler {
            return try await cachedMessageHeadersHandler(folder, sourceID)
        }
        let all = try await store.allMessages(in: mailboxID(for: sourceID))
        return all.filter { $0.folderID == folder.id }
    }

    public func cachedListUnsubscribe(
        for messageID: MessageHeader.ID,
        sourceID: MailSourceID
    ) async -> ListUnsubscribeOptions? {
        guard sourceID.accountID == account.id,
              let resolvedMailboxID = try? await mailboxID(for: sourceID)
        else { return nil }
        return await (try? store.body(for: messageID, mailboxID: resolvedMailboxID))?.listUnsubscribe
    }

    public func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        guard query.hasSearchCriteria else { return [] }
        let all = await store.allMessages
        return all.filter { query.matches($0) }
    }

    public func search(_ query: SearchQuery, sourceID: MailSourceID) async throws -> [MessageHeader] {
        guard query.hasSearchCriteria else { return [] }
        let all = try await store.allMessages(in: mailboxID(for: sourceID))
        return all.filter { query.matches($0) }
    }

    public func calendarEvent(from attachmentID: String) async throws -> CalendarEvent {
        CalendarEvent(
            id: attachmentID,
            title: "Preview meeting",
            start: Date(),
            end: Date().addingTimeInterval(3600),
            location: "Online",
            organizer: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
            attendees: [Correspondent(name: "Henrik Øgård", email: account.emailAddress)],
            description: "Auto-generated by MockBackend."
        )
    }

    public func replyToCalendarInvite(messageID: String, response: AttendeeState) async throws {
        guard capabilities.contains(.serverSideCalendarReply) else {
            throw MailBackendError.notSupported(.serverSideCalendarReply)
        }
        try await store.replyToCalendarInvite(messageID: messageID, response: response)
    }

    public func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState,
        sourceID: MailSourceID
    ) async throws {
        guard capabilities.contains(.serverSideCalendarReply) else {
            throw MailBackendError.notSupported(.serverSideCalendarReply)
        }
        try await store.replyToCalendarInvite(
            messageID: messageID,
            response: response,
            mailboxID: mailboxID(for: sourceID)
        )
    }

    public func subscribeToChanges() -> AsyncStream<MailEvent> {
        store.eventStream()
    }

    public func extensionService<Service>(_ type: Service.Type) -> Service? {
        switch ObjectIdentifier(type) {
        case ObjectIdentifier(ScheduledSendEditing.self)
            where supportsScheduledSend:
            return self as? Service
        case ObjectIdentifier(ScheduledSendManaging.self)
            where supportsScheduledSend:
            return self as? Service
        case ObjectIdentifier(LocalDraftAttachmentProviding.self):
            return self as? Service
        case ObjectIdentifier(CachedListUnsubscribeProviding.self)
            where capabilities.contains(.listUnsubscribeHeaders):
            return self as? Service
        case ObjectIdentifier(AutoReplyManaging.self)
            where capabilities.contains(.autoReply) || capabilities.contains(.sieveVacation):
            return self as? Service
        case ObjectIdentifier(ServerRuleManaging.self) where capabilities.contains(.serverRules):
            return self as? Service
        case ObjectIdentifier(ContactLookupProviding.self) where !contacts.isEmpty:
            return self as? Service
        case ObjectIdentifier(MailImporting.self):
            return self as? Service
        case ObjectIdentifier(SyncHealthReporting.self):
            return self as? Service
        case ObjectIdentifier(SyncHealthRepairing.self):
            return self as? Service
        case ObjectIdentifier(SyncConflictManaging.self):
            return self as? Service
        case ObjectIdentifier(CachedMessageBodyProviding.self):
            return self as? Service
        case ObjectIdentifier(CachedConversationProviding.self)
            where extendedCapabilities.contains(.cachedConversations):
            return self as? Service
        case ObjectIdentifier(RelatedConversationLoading.self)
            where extendedCapabilities.contains(.relatedConversationLoading):
            return self as? Service
        default:
            return nil
        }
    }

    public func cachedConversation(
        around anchor: ConversationMember,
        includeSpamAndTrash: Bool
    ) async throws -> ConversationSnapshot {
        guard let cachedConversationHandler else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await cachedConversationHandler(anchor, includeSpamAndTrash)
    }

    public func loadRelatedConversation(
        around anchor: ConversationMember,
        includeSpamAndTrash: Bool,
        continuation: String?,
        onUpdate: @escaping @Sendable (ConversationSnapshot) async -> Void
    ) async throws -> ConversationSnapshot {
        guard let relatedConversationHandler else {
            throw MailBackendError.notSupported(capabilities)
        }
        return try await relatedConversationHandler(anchor, includeSpamAndTrash, continuation, onUpdate)
    }

    public func contacts(matching query: ContactLookupQuery) async throws -> [ContactLookupResult] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let sourceContacts = contacts.filter { $0.sourceID == query.sourceID }
        let matches = sourceContacts.filter { contact in
            contact.email.lowercased().contains(needle)
                || (contact.displayName ?? "").lowercased().contains(needle)
        }
        return Array(matches.prefix(max(0, query.limit)))
    }

    public func importMessages(_ messages: [ImportedMessage], into folder: Folder) async throws -> MailImportSummary {
        try await store.importMessages(messages, into: folder.id)
    }

    public func vacationResponderSettings(
        for sourceID: MailSourceID
    ) async throws -> [VacationResponderSettings] {
        try await store.vacationResponderSettings(mailboxID: mailboxID(for: sourceID))
    }

    public func saveVacationResponder(
        _ draft: VacationResponderDraft,
        sourceID: MailSourceID
    ) async throws -> VacationResponderSettings {
        guard draft.validationErrors.isEmpty else {
            throw MailBackendError.backendSpecific(message: "Vacation responder settings are invalid.")
        }
        return try await store.saveVacationResponder(draft, mailboxID: mailboxID(for: sourceID))
    }

    public func deleteVacationResponder(id: String, sourceID: MailSourceID) async throws {
        try await store.deleteVacationResponder(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func resetVacationResponderCounter(id: String, sourceID: MailSourceID) async throws {
        try await store.resetVacationResponderCounter(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func serverRules(for sourceID: MailSourceID) async throws -> [ServerRule] {
        try await store.serverRules(mailboxID: mailboxID(for: sourceID))
    }

    public func saveServerRule(_ rule: ServerRule, sourceID: MailSourceID) async throws -> ServerRule {
        try await store.saveServerRule(rule, mailboxID: mailboxID(for: sourceID))
    }

    public func deleteServerRule(id: String, sourceID: MailSourceID) async throws {
        try await store.deleteServerRule(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func reorderServerRules(ids: [String], sourceID: MailSourceID) async throws {
        try await store.reorderServerRules(ids: ids, mailboxID: mailboxID(for: sourceID))
    }

    public func syncHealth(for sourceID: MailSourceID) async -> AccountSyncHealth {
        do {
            return try await store.syncHealth(mailboxID: mailboxID(for: sourceID))
        } catch {
            return AccountSyncHealth(
                sourceID: sourceID,
                state: .providerError,
                lastSuccessfulSyncAt: nil,
                lastErrorDescription: error.localizedDescription,
                indexStatus: .failed(error.localizedDescription),
                cacheSizeBytes: 0,
                pendingMutationCount: 0
            )
        }
    }

    /// Overrides sync health for previews and the UI workbench without network access.
    public func setWorkbenchSyncHealth(_ health: AccountSyncHealth) async throws {
        try await store.setSyncHealthOverride(health, mailboxID: account.id)
    }

    /// Emits determinate sync progress for mailbox chrome previews.
    public func emitWorkbenchSyncProgress(completed: Int, total: Int) async {
        await store.emit(.syncProgress(completed: completed, total: total))
    }

    public func retrySync(for sourceID: MailSourceID) async throws {
        try await store.setSyncHealth(.healthy, mailboxID: mailboxID(for: sourceID))
    }

    public func rebuildSearchIndex(for sourceID: MailSourceID) async throws {
        try await store.rebuildSearchIndex(mailboxID: mailboxID(for: sourceID))
    }

    public func resetLocalCacheAndIndex(for sourceID: MailSourceID) async throws {
        try await store.resetLocalCacheAndIndex(mailboxID: mailboxID(for: sourceID))
    }

    public func clearSyncConflicts(for sourceID: MailSourceID) async throws {
        try await store.dismissAllConflicts(mailboxID: mailboxID(for: sourceID))
    }

    public func retryConflict(id: UUID, sourceID: MailSourceID) async throws {
        try await store.dismissConflict(id: id, mailboxID: mailboxID(for: sourceID))
    }

    public func replayConflicts(for sourceID: MailSourceID) async -> [ReplayConflict] {
        do {
            return try await store.replayConflicts(mailboxID: mailboxID(for: sourceID))
        } catch {
            return []
        }
    }

    public func dismissConflict(id: UUID, sourceID: MailSourceID) async {
        do {
            try await store.dismissConflict(id: id, mailboxID: mailboxID(for: sourceID))
        } catch {
            // Best-effort; no-op on unknown sourceID.
        }
    }

    public func dismissAllConflicts(for sourceID: MailSourceID) async {
        do {
            try await store.dismissAllConflicts(mailboxID: mailboxID(for: sourceID))
        } catch {
            // Best-effort; no-op on unknown sourceID.
        }
    }

    private func mailboxID(for sourceID: MailSourceID) async throws -> Mailbox.ID {
        guard sourceID.accountID == account.id else {
            throw MailBackendError.notFound(id: sourceID.accountID)
        }
        guard await store.hasMailbox(id: sourceID.mailboxID) else {
            throw MailBackendError.notFound(id: sourceID.mailboxID)
        }
        return sourceID.mailboxID
    }

    private static func previewMailboxData(
        mailboxes: [Mailbox],
        primaryFolders: [Folder],
        primaryMessagesByFolder: [String: [MessageHeader]]
    ) -> [Mailbox.ID: MockMailboxData] {
        let primaryMailboxID = mailboxes.first(where: \.isPrimary)?.id ?? mailboxes[0].id
        return Dictionary(mailboxes.map { mailbox in
            if mailbox.id == primaryMailboxID {
                return (
                    mailbox.id,
                    MockMailboxData(
                        folders: primaryFolders,
                        messagesByFolder: primaryMessagesByFolder
                    )
                )
            }
            return (
                mailbox.id,
                MockMailboxData(
                    folders: workPreviewFolders,
                    messagesByFolder: workPreviewMessages(for: mailbox)
                )
            )
        }) { _, latest in latest }
    }

    /// Work mailbox contents: client threads, project delivery, and billing.
    ///
    /// Deliberately unlike the private mailbox in both tone and folder use, so
    /// that switching mailboxes reads as a different account rather than the same
    /// Inbox with a different header.
    private static func workPreviewMessages(for mailbox: Mailbox) -> [String: [MessageHeader]] {
        let me = Correspondent(name: mailbox.displayName, email: mailbox.email)
        let ingrid = Correspondent(name: "Ingrid Halvorsen", email: "ingrid.halvorsen@acme.example")
        let lars = Correspondent(name: "Lars Bjørnstad", email: "lars.bjornstad@acme.example")

        return [
            "inbox": [
                MessageHeader(
                    id: "\(mailbox.id)-inbox-1",
                    threadID: "\(mailbox.id)-thread-stavanger",
                    folderID: "inbox",
                    from: Correspondent(name: "Marte Solheim", email: "marte.solheim@northwind-energy.example"),
                    to: [me],
                    subject: "Stavanger rollout — terminal go-live window",
                    snippet: "We can take the terminal offline Tuesday 06:00–09:00. Does that hold on your side?",
                    date: previewDate(minutesAgo: 25),
                    isRead: false,
                    isFlagged: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-2",
                    threadID: "\(mailbox.id)-thread-stavanger",
                    folderID: "inbox",
                    from: ingrid,
                    to: [me, Correspondent(name: "Marte Solheim", email: "marte.solheim@northwind-energy.example")],
                    subject: "Re: Stavanger rollout — terminal go-live window",
                    snippet: "Tuesday works. I'll have the rollback plan signed off Monday afternoon.",
                    date: previewDate(hoursAgo: 1, minutesAgo: 40),
                    isRead: false,
                    isAnswered: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-3",
                    threadID: "\(mailbox.id)-thread-harbourdata",
                    folderID: "inbox",
                    from: Correspondent(name: "GitHub", email: "notifications@github.com"),
                    to: [me],
                    subject: "[acme/harbour-data] Berth schema migration ready for review",
                    snippet: "Adds the berth-allocation retry queue and a handful of unit tests.",
                    date: previewDate(hoursAgo: 3),
                    isRead: false
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-4",
                    threadID: "\(mailbox.id)-thread-invoice",
                    folderID: "inbox",
                    from: Correspondent(name: "Ledger & Co", email: "accounts@ledger-co.example"),
                    to: [me],
                    subject: "Q2 invoicing — two entries missing a project code",
                    snippet: "Invoice 2026-0184 and 2026-0191 are unassigned. Can you confirm the codes?",
                    date: previewDate(hoursAgo: 6),
                    isRead: false
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-5",
                    threadID: "\(mailbox.id)-thread-harbour",
                    folderID: "inbox",
                    from: Correspondent(name: "Harbour Logistics", email: "notices@harbour-logistics.example"),
                    to: [me],
                    subject: "Weekly delivery digest — week 33",
                    snippet: "No missed windows this week. Trondheim depot is back to normal capacity.",
                    date: previewDate(daysAgo: 1, hoursAgo: 2),
                    isRead: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-6",
                    threadID: "\(mailbox.id)-thread-contract",
                    folderID: "inbox",
                    from: Correspondent(name: "Hale & Reed Legal", email: "contact@hale-reed.example"),
                    to: [me],
                    subject: "Meridian Media — framework agreement, redlined draft",
                    snippet: "Attached is the redline. Section 7 on data processing needs your read.",
                    date: previewDate(daysAgo: 2),
                    isRead: true,
                    hasAttachments: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-7",
                    threadID: "\(mailbox.id)-thread-linear",
                    folderID: "inbox",
                    from: Correspondent(name: "Linear", email: "notifications@linear.app"),
                    to: [me],
                    subject: "HRB-204 moved to In Progress",
                    snippet: "Berth allocation retries are now linked to the Stavanger milestone.",
                    date: previewDate(daysAgo: 2, hoursAgo: 5),
                    isRead: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-8",
                    threadID: "\(mailbox.id)-thread-vercel",
                    folderID: "inbox",
                    from: Correspondent(name: "Vercel", email: "deployments@vercel.com"),
                    to: [me],
                    subject: "Production deployment succeeded",
                    snippet: "harbour-data deployed from main with no build warnings.",
                    date: previewDate(daysAgo: 3),
                    isRead: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-inbox-9",
                    threadID: "\(mailbox.id)-thread-figma",
                    folderID: "inbox",
                    from: Correspondent(name: "Figma", email: "updates@figma.com"),
                    to: [me],
                    subject: "Comments on Terminal dashboard",
                    snippet: "Marte left two comments on the berth timeline layout.",
                    date: previewDate(daysAgo: 4),
                    isRead: false
                )
            ],
            "sent": [
                MessageHeader(
                    id: "\(mailbox.id)-sent-1",
                    threadID: "\(mailbox.id)-thread-stavanger",
                    folderID: "sent",
                    from: me,
                    to: [ingrid],
                    subject: "Re: Stavanger rollout — terminal go-live window",
                    snippet: "Confirmed for Tuesday. I'll be on site from 05:30.",
                    date: previewDate(hoursAgo: 1),
                    isRead: true
                ),
                MessageHeader(
                    id: "\(mailbox.id)-sent-2",
                    threadID: "\(mailbox.id)-thread-solvang",
                    folderID: "sent",
                    from: me,
                    to: [Correspondent(name: "Meridian Media", email: "studio@meridian-media.example")],
                    subject: "Revised scope and estimate",
                    snippet: "Two phases instead of three. Estimate lands at NOK 480 000 ex. VAT.",
                    date: previewDate(daysAgo: 3),
                    isRead: true
                )
            ],
            "clients-northwind": [
                MessageHeader(
                    id: "\(mailbox.id)-bergensfjord-1",
                    threadID: "\(mailbox.id)-thread-bergensfjord",
                    folderID: "clients-northwind",
                    from: Correspondent(name: "Marte Solheim", email: "marte.solheim@northwind-energy.example"),
                    to: [me],
                    subject: "Access request for the Kollsnes VPN",
                    snippet: "Security will issue the certificate once you send the device serial.",
                    date: previewDate(daysAgo: 5),
                    isRead: true
                )
            ],
            "clients-harbour": [
                MessageHeader(
                    id: "\(mailbox.id)-norhavn-1",
                    threadID: "\(mailbox.id)-thread-norhavn-ops",
                    folderID: "clients-harbour",
                    from: Correspondent(name: "Tor Eide", email: "tor.eide@harbour-logistics.example"),
                    to: [me],
                    subject: "Depot handover notes — Trondheim",
                    snippet: "Night shift reports the scanner sync clears in under a minute now.",
                    date: previewDate(daysAgo: 8),
                    isRead: true
                )
            ],
            "projects-stavanger": [
                MessageHeader(
                    id: "\(mailbox.id)-kystlink-1",
                    threadID: "\(mailbox.id)-thread-kystlink-plan",
                    folderID: "projects-stavanger",
                    from: lars,
                    to: [me],
                    subject: "Rollback plan, v3",
                    snippet: "Cut the manual step — the terminal restores from the previous snapshot.",
                    date: previewDate(daysAgo: 4),
                    isRead: true,
                    hasAttachments: true
                )
            ],
            "projects-harbourdata": [
                MessageHeader(
                    id: "\(mailbox.id)-havnedata-1",
                    threadID: "\(mailbox.id)-thread-havnedata-plan",
                    folderID: "projects-harbourdata",
                    from: ingrid,
                    to: [me],
                    subject: "Migration window moved to week 36",
                    snippet: "Bergen asked for a week's buffer after the audit. Everything else holds.",
                    date: previewDate(daysAgo: 9),
                    isRead: true
                )
            ],
            "contracts": [
                MessageHeader(
                    id: "\(mailbox.id)-contracts-1",
                    threadID: "\(mailbox.id)-thread-contracts",
                    folderID: "contracts",
                    from: Correspondent(name: "Hale & Reed Legal", email: "contact@hale-reed.example"),
                    to: [me],
                    subject: "Countersigned: Harbour Logistics maintenance agreement",
                    snippet: "Both parties have signed. Term runs to 31 December 2027.",
                    date: previewDate(daysAgo: 21),
                    isRead: false,
                    hasAttachments: true
                )
            ],
            "invoicing": [
                MessageHeader(
                    id: "\(mailbox.id)-invoicing-1",
                    threadID: "\(mailbox.id)-thread-invoicing",
                    folderID: "invoicing",
                    from: Correspondent(name: "Stripe", email: "receipts@stripe.com"),
                    to: [me],
                    subject: "Payment received — invoice 2026-0177",
                    snippet: "NOK 212 500 settled from Northwind Energy.",
                    date: previewDate(daysAgo: 11),
                    isRead: false
                ),
                MessageHeader(
                    id: "\(mailbox.id)-invoicing-2",
                    threadID: "\(mailbox.id)-thread-invoicing-2",
                    folderID: "invoicing",
                    from: Correspondent(name: "Ledger & Co", email: "accounts@ledger-co.example"),
                    to: [me],
                    subject: "Reminder: July hours due Friday",
                    snippet: "Two projects are still open in the timesheet export.",
                    date: previewDate(daysAgo: 14),
                    isRead: false
                )
            ],
            "follow-up": [
                MessageHeader(
                    id: "\(mailbox.id)-followup-1",
                    threadID: "\(mailbox.id)-thread-followup",
                    folderID: "follow-up",
                    from: Correspondent(name: "Meridian Media", email: "studio@meridian-media.example"),
                    to: [me],
                    subject: "Waiting on: brand assets for the terminal displays",
                    snippet: "You snoozed this until the Stavanger go-live date was confirmed.",
                    date: previewDate(daysAgo: 6),
                    isRead: true
                )
            ]
        ]
    }
}

// MARK: - Preview fixtures

public extension BrevAccount {
    /// Stable preview identity. Email is `@example.org`, never routed.
    static let preview = BrevAccount(
        id: "preview-account",
        displayName: "Henrik Øgård",
        emailAddress: "henrik@ogard.example",
        backendIdentifier: BrevAccount.demoBackendIdentifier,
        backendDisplayName: "Demo"
    )
}

public extension BackendCapabilities {
    /// The full preview capability set, used by previews
    /// that want every code path enabled.
    static let full: BackendCapabilities = [
        .serverSideSearch,
        .serverSideThreading,
        .labels,
        .flagColors,
        .snooze,
        .serverSideCalendarReply,
        .serverSideIcsRender,
        .aiWriter,
        .oauthAuth,
        .providerAPI,
        .multipleMailboxes,
        .sharedMailboxes,
        .serverRules,
        .autoReply,
        .aliases,
        .serverSignatures,
        .listUnsubscribeHeaders,
        .providerSyncHealth,
        .folderCreate,
        .folderRename,
        .folderDelete,
        .folderFlush,
        .junkAPI,
        .blockSender
    ]
}

public extension MockBackend {
    static func previewMailboxes(for account: BrevAccount = .preview) -> [Mailbox] {
        [
            Mailbox(
                id: account.id,
                email: account.emailAddress,
                displayName: "\(account.displayName) (private)",
                isPrimary: true
            ),
            Mailbox(
                id: "\(account.id)-work",
                email: workPreviewEmail,
                displayName: "\(account.displayName) (work)"
            )
        ]
    }

    static func previewContacts(accountID: BrevAccount.ID = BrevAccount.preview.id,
                                mailboxID: Mailbox.ID) -> [ContactLookupResult] {
        let sourceID = MailSourceID(accountID: accountID, mailboxID: mailboxID)
        return [
            ContactLookupResult(
                id: "contact-sigrid",
                displayName: "Sigrid Moen",
                email: "sigrid.moen@example.org",
                sourceID: sourceID
            ),
            ContactLookupResult(
                id: "contact-anders",
                displayName: "Anders Vik",
                email: "anders.vik@example.org",
                sourceID: sourceID
            ),
            ContactLookupResult(
                id: "contact-kari",
                displayName: "Kari Nesheim",
                email: "kari@nesheim-architects.example",
                sourceID: sourceID
            ),
            ContactLookupResult(
                id: "contact-ingrid",
                displayName: "Ingrid Halvorsen",
                email: "ingrid.halvorsen@acme.example",
                sourceID: sourceID
            )
        ]
    }

    /// Fixed address for the work mailbox.
    ///
    /// Its own domain rather than a suffix on the private one — the two mailboxes
    /// exist in the mock so that switching between them is visible, and sharing a
    /// domain made them look like aliases of one account.
    static let workPreviewEmail = "henrik.ogard@acme.example"

    /// Private mailbox: a household filing tree.
    static let previewFolders: [Folder] = [
        Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 6, totalCount: 16),
        Folder(id: "drafts", name: "Drafts", role: .drafts, unreadCount: 0, totalCount: 1),
        Folder(id: "sent", name: "Sent", role: .sent, unreadCount: 0, totalCount: 47),
        Folder(id: "archive", name: "Archive", role: .archive, unreadCount: 0, totalCount: 312),
        Folder(id: "archive-home", name: "Home", role: .custom, parentID: "archive"),
        Folder(id: "archive-travel", name: "Travel", role: .custom, parentID: "archive"),
        Folder(id: "archive-receipts", name: "Receipts", role: .custom, parentID: "archive"),
        Folder(
            id: "archive-receipts-licenses",
            name: "Software",
            role: .custom,
            parentID: "archive-receipts"
        ),
        Folder(
            id: "archive-newsletters",
            name: "Newsletters",
            role: .custom,
            parentID: "archive",
            unreadCount: 1479,
            totalCount: 1479
        ),
        Folder(id: "mailspring", name: "Imported", role: .custom),
        Folder(id: "mailspring-snoozed", name: "Snoozed", role: .snoozed, parentID: "mailspring"),
        Folder(id: "promotions", name: "Promotions", role: .custom, unreadCount: 591, totalCount: 591),
        Folder(id: "social-networks", name: "Social", role: .custom, unreadCount: 14, totalCount: 14),
        Folder(id: "spam", name: "Spam", role: .spam, unreadCount: 87, totalCount: 87),
        Folder(id: "trash", name: "Trash", role: .trash, unreadCount: 1, totalCount: 1)
    ]

    /// Work mailbox: a client-and-delivery tree, deliberately unlike the private
    /// one so that switching mailboxes is obvious at a glance.
    static let workPreviewFolders: [Folder] = [
        Folder(id: "inbox", name: "Inbox", role: .inbox, unreadCount: 5, totalCount: 21),
        Folder(id: "drafts", name: "Drafts", role: .drafts, unreadCount: 0, totalCount: 2),
        Folder(id: "sent", name: "Sent", role: .sent, unreadCount: 0, totalCount: 128),
        Folder(id: "clients", name: "Clients", role: .custom),
        Folder(id: "clients-northwind", name: "Northwind Energy", role: .custom, parentID: "clients"),
        Folder(id: "clients-harbour", name: "Harbour Logistics", role: .custom, parentID: "clients"),
        Folder(id: "clients-meridian", name: "Meridian Media", role: .custom, parentID: "clients"),
        Folder(id: "projects", name: "Projects", role: .custom),
        Folder(id: "projects-stavanger", name: "Stavanger Rollout", role: .custom, parentID: "projects"),
        Folder(id: "projects-harbourdata", name: "Harbour Data Migration", role: .custom, parentID: "projects"),
        Folder(id: "contracts", name: "Contracts", role: .custom, unreadCount: 1, totalCount: 34),
        Folder(id: "invoicing", name: "Invoicing", role: .custom, unreadCount: 2, totalCount: 96),
        Folder(id: "archive", name: "Archive", role: .archive, unreadCount: 0, totalCount: 874),
        // `.custom`, not `.snoozed`: the sidebar renders well-known roles under
        // their canonical name, so a `.snoozed` role would display as "Snoozed".
        Folder(id: "follow-up", name: "Follow-up", role: .custom, unreadCount: 0, totalCount: 5),
        Folder(id: "spam", name: "Spam", role: .spam, unreadCount: 12, totalCount: 12),
        Folder(id: "trash", name: "Trash", role: .trash, unreadCount: 0, totalCount: 3)
    ]

    private static func previewDate(daysAgo: Int = 0, hoursAgo: Int = 0, minutesAgo: Int = 0) -> Date {
        Date().addingTimeInterval(
            -TimeInterval(daysAgo * 86400 + hoursAgo * 3600 + minutesAgo * 60)
        )
    }

    static let previewMessages: [String: [MessageHeader]] = [
        "inbox": [
            MessageHeader(
                id: "m1",
                threadID: "thread-standup",
                folderID: "inbox",
                from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Hytte weekend in Hemsedal — 12–14 September",
                snippet: "Booked the cabin for three nights. Invite attached so it lands in your calendar.",
                date: previewDate(hoursAgo: 1),
                isRead: false,
                hasAttachments: true
            ),
            MessageHeader(
                id: "m17",
                threadID: "thread-standup",
                folderID: "inbox",
                from: Correspondent(name: "Jonas Ryland", email: "jonas.ryland@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Hytte weekend in Hemsedal — 12–14 September",
                snippet: "Count me in. I can drive if we leave from Bergen on the Friday afternoon.",
                date: previewDate(minutesAgo: 45),
                isRead: false,
                isFlagged: true
            ),
            MessageHeader(
                id: "m2",
                threadID: "t2",
                folderID: "inbox",
                from: Correspondent(name: "Westland Power", email: "billing@westland-power.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Your July electricity bill is ready",
                snippet: "NOK 1 284 for 612 kWh. Due 20 August. Spot price averaged 74 øre.",
                date: previewDate(hoursAgo: 2),
                isRead: false
            ),
            MessageHeader(
                id: "m18",
                threadID: "thread-standup",
                folderID: "inbox",
                from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Re: Hytte weekend in Hemsedal — 12–14 September",
                snippet: "Added the packing list and the trail map to the shared album.",
                date: previewDate(hoursAgo: 2, minutesAgo: 10),
                isRead: true,
                isAnswered: true
            ),
            MessageHeader(
                id: "m5",
                threadID: "t5",
                folderID: "inbox",
                from: Correspondent(name: "Harbour View Residents", email: "board@harbourview-residents.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Garage door remotes are being reprogrammed",
                snippet: "Bring your remote to the board meeting on Thursday, or collect a new one after.",
                date: previewDate(hoursAgo: 3, minutesAgo: 20),
                isRead: false
            ),
            MessageHeader(
                id: "m6",
                threadID: "t6",
                folderID: "inbox",
                from: Correspondent(name: "Bergen Photo Club", email: "hello@bergen-photo-club.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Autumn programme and darkroom slots",
                snippet: "Booking opens Monday. The Fløyen night-shoot filled up in a day last year.",
                date: previewDate(hoursAgo: 5),
                isRead: true
            ),
            // A four-message design review thread (multiple senders) so
            // nested/threaded rendering has a longer conversation to expand.
            MessageHeader(
                id: "md1",
                threadID: "thread-design",
                folderID: "inbox",
                from: Correspondent(name: "Kari Nesheim", email: "kari@nesheim-architects.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Kitchen drawings — final review",
                snippet: "Two changes before we order: the island depth and the window sill height.",
                date: previewDate(hoursAgo: 6),
                isRead: false
            ),
            MessageHeader(
                id: "md2",
                threadID: "thread-design",
                folderID: "inbox",
                from: Correspondent(name: "Anders Vik", email: "anders.vik@example.org"),
                to: [
                    Correspondent(email: "henrik@ogard.example"),
                    Correspondent(name: "Kari Nesheim", email: "kari@nesheim-architects.example")
                ],
                subject: "Re: Kitchen drawings — final review",
                snippet: "Agreed on the island depth. I can start the week after the plumber.",
                date: previewDate(hoursAgo: 5),
                isRead: true,
                isAnswered: true
            ),
            MessageHeader(
                id: "md3",
                threadID: "thread-design",
                folderID: "inbox",
                from: Correspondent(name: "Kari Nesheim", email: "kari@nesheim-architects.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Kitchen drawings — final review",
                snippet: "Looks good. One more thing: the sill has to clear the tap by 40 mm.",
                date: previewDate(hoursAgo: 4),
                isRead: true
            ),
            MessageHeader(
                id: "md4",
                threadID: "thread-design",
                folderID: "inbox",
                from: Correspondent(name: "Anders Vik", email: "anders.vik@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Kitchen drawings — final review",
                snippet: "Redrawn — ready for your sign-off whenever you have a minute.",
                date: previewDate(hoursAgo: 3, minutesAgo: 30),
                isRead: false,
                isFlagged: true
            ),
            // A three-message beta feedback thread between two people.
            MessageHeader(
                id: "mb1",
                threadID: "thread-beta",
                folderID: "inbox",
                from: Correspondent(name: "Jonas Ryland", email: "jonas.ryland@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Boat share — end of season list",
                snippet: "Collected everyone's notes. Mostly small jobs, two that need a yard.",
                date: previewDate(hoursAgo: 30),
                isRead: true
            ),
            MessageHeader(
                id: "mb2",
                threadID: "thread-beta",
                folderID: "inbox",
                from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
                to: [Correspondent(name: "Jonas Ryland", email: "jonas.ryland@example.org")],
                subject: "Re: Boat share — end of season list",
                snippet: "Booked the yard for both. Can you confirm the winch is still slipping?",
                date: previewDate(hoursAgo: 28),
                isRead: true,
                isAnswered: true
            ),
            MessageHeader(
                id: "mb3",
                threadID: "thread-beta",
                folderID: "inbox",
                from: Correspondent(name: "Jonas Ryland", email: "jonas.ryland@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Boat share — end of season list",
                snippet: "Confirmed — it slips under load only. Added a short video.",
                date: previewDate(hoursAgo: 26),
                isRead: false,
                hasAttachments: true
            ),
            MessageHeader(
                id: "m3",
                threadID: "t3",
                folderID: "inbox",
                from: Correspondent(name: "Coastal Bank", email: "no-reply@coastalbank.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Your July statement is ready",
                snippet: "No action needed. Sign in to view the full statement.",
                date: previewDate(daysAgo: 1),
                isRead: true
            ),
            MessageHeader(
                id: "m7",
                threadID: "t7",
                folderID: "inbox",
                from: Correspondent(name: "Bergen Hiking Club", email: "walks@bergen-hiking-club.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "This week's guided walks",
                snippet: "Three walks out of Ulriken, and the cabin key rota for September.",
                date: previewDate(daysAgo: 1, hoursAgo: 4),
                isRead: true
            ),
            MessageHeader(
                id: "m19",
                threadID: "thread-standup",
                folderID: "inbox",
                from: Correspondent(name: "Jonas Ryland", email: "jonas.ryland@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Hytte weekend in Hemsedal — 12–14 September",
                snippet: "Reminder: the road over Hemsedalsfjellet closes for maintenance Sunday night.",
                date: previewDate(hoursAgo: 4, minutesAgo: 50),
                isRead: true
            ),
            MessageHeader(
                id: "m4",
                threadID: "t4",
                folderID: "inbox",
                from: Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: weekend plans",
                snippet: "Saturday works. I'll bring the coffee and the thermos.",
                date: previewDate(daysAgo: 2),
                isRead: true,
                isFlagged: true,
                isAnswered: true
            ),
            MessageHeader(
                id: "m20",
                threadID: "t20",
                folderID: "inbox",
                from: Correspondent(name: "Harbour View Residents", email: "board@harbourview-residents.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Water meter reading due",
                snippet: "Please send your reading before Friday so the shared bill can be split.",
                date: previewDate(daysAgo: 4),
                isRead: true
            ),
            MessageHeader(
                id: "m21",
                threadID: "t20",
                folderID: "inbox",
                from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
                to: [Correspondent(name: "Harbour View Residents", email: "board@harbourview-residents.example")],
                subject: "Re: Water meter reading due",
                snippet: "Sent — 0142 as of this morning. Photo attached in case it helps.",
                date: previewDate(daysAgo: 3, hoursAgo: 12),
                isRead: true,
                isAnswered: true
            ),
            MessageHeader(
                id: "m22",
                threadID: "t20",
                folderID: "inbox",
                from: Correspondent(name: "Harbour View Residents", email: "board@harbourview-residents.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Re: Re: Water meter reading due",
                snippet: "Received, thanks. The split will show on the September invoice.",
                date: previewDate(daysAgo: 3, hoursAgo: 2),
                isRead: false,
                isFlagged: true
            ),
            MessageHeader(
                id: "m8",
                threadID: "t8",
                folderID: "inbox",
                from: Correspondent(name: "Hemsedal Cabin Owners", email: "board@hemsedal-cabins.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Road fee and winter ploughing",
                snippet: "This season's fee is unchanged. Ploughing starts once there is 15 cm.",
                date: previewDate(daysAgo: 3),
                isRead: false
            ),
            MessageHeader(
                id: "m9",
                threadID: "t9",
                folderID: "inbox",
                from: Correspondent(name: "Nordfjord Sports Club", email: "members@nordfjord-sports.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Membership renewal for the coming season",
                snippet: "Renew before 1 September to keep your hall booking slot.",
                date: previewDate(daysAgo: 5),
                isRead: true
            ),
            MessageHeader(
                id: "m10",
                threadID: "t10",
                folderID: "inbox",
                from: Correspondent(name: "Coastline Broadband", email: "support@coastline-broadband.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Fibre work in your street next week",
                snippet: "Expect a short outage Tuesday morning while the cabinet is swapped.",
                date: previewDate(daysAgo: 8),
                isRead: false
            ),
            MessageHeader(
                id: "m11",
                threadID: "t11",
                folderID: "inbox",
                from: Correspondent(name: "Bergen Library", email: "no-reply@bergen-library.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Your reservation is ready for pickup",
                snippet: "Hold expires in seven days at the Strømgaten desk.",
                date: previewDate(daysAgo: 11),
                isRead: true
            ),
            MessageHeader(
                id: "m12",
                threadID: "t12",
                folderID: "inbox",
                from: Correspondent(name: "Coastal Bank", email: "no-reply@coastalbank.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Standing order executed",
                snippet: "NOK 4 200 transferred to the shared cabin account as scheduled.",
                date: previewDate(daysAgo: 16),
                isRead: true
            ),
            MessageHeader(
                id: "m13",
                threadID: "t13",
                folderID: "inbox",
                from: Correspondent(name: "GitHub", email: "noreply@github.com"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "New sign-in to your GitHub account",
                snippet: "A successful sign-in was recorded from a new browser in Bergen.",
                date: previewDate(daysAgo: 20),
                isRead: true
            ),
            MessageHeader(
                id: "m14",
                threadID: "t14",
                folderID: "inbox",
                from: Correspondent(name: "Bryggen Coffee Roasters", email: "receipts@bryggen-coffee.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Receipt from Bryggen Coffee Roasters",
                snippet: "Cappuccino and a skillingsbolle, paid with card ending in 0424.",
                date: previewDate(daysAgo: 25),
                isRead: true
            ),
            MessageHeader(
                id: "m15",
                threadID: "t15",
                folderID: "inbox",
                from: Correspondent(name: "Bergen Photo Club", email: "hello@bergen-photo-club.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Notes and images from the harbour walk",
                snippet: "Everyone's picks from the Bryggen evening are up in the shared album.",
                date: previewDate(daysAgo: 36),
                isRead: false
            ),
            MessageHeader(
                id: "m16",
                threadID: "t16",
                folderID: "inbox",
                from: Correspondent(name: "The Coastal Post", email: "editors@coastal-post.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "This month from the west coast",
                snippet: "Ferry timetable changes, the new coastal path, and a long read from Sunnmøre.",
                date: previewDate(daysAgo: 42),
                isRead: true
            )
        ],
        "sent": [
            MessageHeader(
                id: "s1",
                threadID: "t4",
                folderID: "sent",
                from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
                to: [Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org")],
                subject: "weekend plans",
                snippet: "Are you around Saturday?",
                date: previewDate(daysAgo: 2, hoursAgo: 7),
                isRead: true
            ),
            MessageHeader(
                id: "s2",
                threadID: "t4",
                folderID: "sent",
                from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
                to: [Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org")],
                subject: "Re: weekend plans",
                snippet: "Monday morning works better for me, so let's swap.",
                date: previewDate(daysAgo: 3),
                isRead: true
            ),
            MessageHeader(
                id: "s3",
                threadID: "t4",
                folderID: "sent",
                from: Correspondent(name: "Henrik Øgård", email: "henrik@ogard.example"),
                to: [Correspondent(name: "Sigrid Moen", email: "sigrid.moen@example.org")],
                subject: "Re: Re: weekend plans",
                snippet: "Let's keep it for Sunday, 10:30 in the morning.",
                date: previewDate(daysAgo: 1),
                isRead: true,
                isAnswered: true
            )
        ],
        "archive-newsletters": [
            MessageHeader(
                id: "newsletter-1",
                threadID: "newsletter-thread-1",
                folderID: "archive-newsletters",
                from: Correspondent(name: "The Coastal Post", email: "editors@coastal-post.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Weekend edition",
                snippet: "A short roundup from the coast, and where the northern lights were seen.",
                date: previewDate(daysAgo: 12),
                isRead: false
            )
        ],
        "archive-receipts-licenses": [
            MessageHeader(
                id: "license-1",
                threadID: "license-thread-1",
                folderID: "archive-receipts-licenses",
                from: Correspondent(name: "Apple", email: "no_reply@email.apple.com"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Your subscription receipt",
                snippet: "Renewed for another year. NOK 1 490 charged to the card on file.",
                date: previewDate(daysAgo: 34),
                isRead: true
            )
        ],
        "mailspring-snoozed": [
            MessageHeader(
                id: "mailspring-snoozed-1",
                threadID: "mailspring-thread-1",
                folderID: "mailspring-snoozed",
                from: Correspondent(name: "Anders Vik", email: "anders.vik@example.org"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "Snoozed: chase the plumber's quote",
                snippet: "You snoozed this message to resurface this morning.",
                date: previewDate(daysAgo: 6),
                isRead: false
            )
        ],
        "promotions": [
            MessageHeader(
                id: "promo-1",
                threadID: "promo-thread-1",
                folderID: "promotions",
                from: Correspondent(name: "Summit Outdoor", email: "offers@summit-outdoor.example"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "End-of-season sale on shell jackets",
                snippet: "Up to 40% off last season's shells, in store on Torgallmenningen.",
                date: previewDate(daysAgo: 7),
                isRead: false
            )
        ],
        "social-networks": [
            MessageHeader(
                id: "social-1",
                threadID: "social-thread-1",
                folderID: "social-networks",
                from: Correspondent(name: "Mastodon", email: "notifications@mastodon.social"),
                to: [Correspondent(email: "henrik@ogard.example")],
                subject: "New mentions this week",
                snippet: "You have 3 new mentions and 5 reactions waiting.",
                date: previewDate(daysAgo: 9),
                isRead: false
            )
        ]
    ]
}

// MARK: - Internal store

private struct MockMailboxData {
    var savedDrafts: [String: Draft] = [:]
    var attachmentDraftIDs: [String: String] = [:]
    var folders: [Folder]
    var messagesByFolder: [String: [MessageHeader]]
    var messageBodies: [String: MessageBody]
    var attachmentsByID: [String: Attachment]
    var attachmentDataByID: [String: Data]
    var vacationResponders: [VacationResponderSettings]
    var serverRules: [ServerRule]
    var syncHealth: AccountSyncHealth?
    /// Undismissed replay conflicts for this mailbox.
    var replayConflicts: [ReplayConflict]

    init(folders: [Folder], messagesByFolder: [String: [MessageHeader]]) {
        self.folders = folders
        self.messagesByFolder = messagesByFolder
        let previewAttachmentSeed = Self.previewAttachmentSeed(for: messagesByFolder)
        messageBodies = previewAttachmentSeed.messageBodies
        attachmentsByID = previewAttachmentSeed.attachmentsByID
        attachmentDataByID = previewAttachmentSeed.attachmentDataByID
        vacationResponders = []
        serverRules = []
        syncHealth = nil
        replayConflicts = []
    }

    private static func previewAttachmentSeed(for messagesByFolder: [String: [MessageHeader]]) -> MockAttachmentSeed {
        guard messagesByFolder.values.flatMap({ $0 }).contains(where: { $0.id == "m1" && $0.hasAttachments }) else {
            return .empty
        }

        let data = Data(previewCalendarInvite.utf8)
        let attachment = Attachment(
            id: previewCalendarAttachmentID,
            name: "hytte-weekend.ics",
            mimeType: "text/calendar",
            sizeBytes: data.count,
            resource: previewCalendarAttachmentID
        )
        return MockAttachmentSeed(
            messageBodies: [
                "m1": MessageBody(
                    messageID: "m1",
                    html: """
                    <p>Quick recap from yesterday: three open threads, all triaged.</p>
                    <p>The cabin weekend invite is attached.</p>
                    """,
                    plainText: """
                    Quick recap from yesterday: three open threads, all triaged.
                    The cabin weekend invite is attached.
                    """,
                    attachments: [attachment]
                )
            ],
            attachmentsByID: [attachment.id: attachment],
            attachmentDataByID: [attachment.id: data]
        )
    }

    private static let previewCalendarAttachmentID = "preview-calendar-m1"

    private static let previewCalendarInvite = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//Brev//MockBackend//EN
    BEGIN:VEVENT
    UID:demo-hytte-weekend@example.org
    DTSTAMP:20260528T120000Z
    DTSTART:20260911T160000Z
    DTEND:20260913T140000Z
    SUMMARY:Hytte weekend in Hemsedal
    ORGANIZER;CN=Sigrid Moen:mailto:sigrid.moen@example.org
    ATTENDEE;CN=Henrik Øgård:mailto:henrik@ogard.example
    END:VEVENT
    END:VCALENDAR
    """
}

private struct MockAttachmentSeed {
    static let empty = MockAttachmentSeed(
        messageBodies: [:],
        attachmentsByID: [:],
        attachmentDataByID: [:]
    )

    let messageBodies: [String: MessageBody]
    let attachmentsByID: [String: Attachment]
    let attachmentDataByID: [String: Data]
}

private actor Store {
    var mailboxes: [Mailbox]
    var activeMailboxID: Mailbox.ID
    var dataByMailboxID: [Mailbox.ID: MockMailboxData]
    private(set) var blockedSenders: Set<String> = []
    private var continuations: [UUID: AsyncStream<MailEvent>.Continuation] = [:]
    private let accountID: BrevAccount.ID
    private let journal: MockSendJournal?
    private let now: @Sendable () -> Date
    private let automaticDeliveryEnabled: Bool
    private let scheduledSendSnapshot: MockScheduledSendSnapshot
    private let initialDataByMailboxID: [Mailbox.ID: MockMailboxData]
    private var journalRecords: [MockSendJournalRecord] = []
    private var journalLoadError: (any Error)?
    private var isPaused = false
    private var isPurged = false
    private var workerGeneration = 0
    private var workerTask: Task<Void, Never>?
    private var retryAfter: [String: Date] = [:]

    init(
        mailboxes: [Mailbox],
        dataByMailboxID: [Mailbox.ID: MockMailboxData],
        accountID: BrevAccount.ID,
        journal: MockSendJournal?,
        now: @escaping @Sendable () -> Date,
        automaticDeliveryEnabled: Bool,
        scheduledSendSnapshot: MockScheduledSendSnapshot
    ) {
        initialDataByMailboxID = dataByMailboxID
        self.mailboxes = mailboxes
        activeMailboxID = mailboxes.first(where: \.isPrimary)?.id ?? mailboxes[0].id
        self.accountID = accountID
        self.journal = journal
        self.now = now
        self.automaticDeliveryEnabled = automaticDeliveryEnabled
        self.scheduledSendSnapshot = scheduledSendSnapshot
        if let journal {
            do {
                let records = try journal.load()
                self.dataByMailboxID = Self.projectJournalChanges(
                    previousRecords: [],
                    records: records,
                    mailboxes: mailboxes,
                    current: dataByMailboxID
                )
                journalRecords = records
            } catch {
                journalLoadError = error
                self.dataByMailboxID = dataByMailboxID
            }
        } else {
            self.dataByMailboxID = dataByMailboxID
        }
        scheduledSendSnapshot.replace(with: Self.scheduledEntries(from: journalRecords))
    }

    deinit {
        workerTask?.cancel()
    }

    func resume() throws {
        try reloadJournalRecords()
        isPurged = false
        isPaused = false
        deliverDueScheduledSends()
        startWorkerIfNeeded(restart: true)
    }

    func pause() {
        isPaused = true
        stopWorker()
    }

    func startWorkerIfNeeded(restart: Bool = false) {
        if restart { stopWorker() }
        guard automaticDeliveryEnabled, !isPaused,
              journalLoadError == nil,
              journalRecords.contains(where: { $0.state == .queued }),
              workerTask == nil else { return }
        workerGeneration += 1
        let generation = workerGeneration
        workerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.workerDelay(generation: generation) else { break }
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                }
                guard !Task.isCancelled else { break }
                guard let shouldContinue = await self?.deliverWorkerTick(generation: generation),
                      shouldContinue else { break }
            }
            await self?.finishWorker(generation: generation)
        }
    }

    private func stopWorker() {
        workerGeneration += 1
        workerTask?.cancel()
        workerTask = nil
    }

    private func workerDelay(generation: Int) -> TimeInterval? {
        guard generation == workerGeneration, !isPaused, journalLoadError == nil else { return nil }
        let dates = journalRecords.compactMap { record -> Date? in
            guard record.state == .queued,
                  dataByMailboxID[record.sourceID.mailboxID] != nil,
                  let due = record.scheduledFor else { return nil }
            return max(due, record.nextAttemptAt ?? retryAfter[record.recordID] ?? due)
        }
        guard let next = dates.min() else { return nil }
        return min(max(0, next.timeIntervalSince(now())), 60)
    }

    private func deliverWorkerTick(generation: Int) -> Bool {
        guard generation == workerGeneration, !isPaused, journalLoadError == nil else { return false }
        deliverDueScheduledSends()
        return generation == workerGeneration && !isPaused && journalLoadError == nil
    }

    private func finishWorker(generation: Int) {
        guard generation == workerGeneration else { return }
        workerTask = nil
    }

    func ensureActive() throws {
        guard !isPurged, journalLoadError == nil else { throw Self.storageError }
    }

    func scheduledDraft(id: String) throws -> Draft? {
        guard journalLoadError == nil else { throw Self.storageError }
        return journalRecords.first { $0.scheduleID == id && $0.state == .queued }?.draft
    }

    func schedule(draft: Draft, scheduledFor: Date, mailboxID: Mailbox.ID) throws -> SendResult {
        try ensureActive()
        try reloadJournalRecords()
        guard scheduledFor.timeIntervalSince1970.isFinite else { throw ScheduledSendEditingError.invalidDate }
        guard var mailboxData = dataByMailboxID[mailboxID] else { throw MailBackendError.notFound(id: mailboxID) }
        guard journalLoadError == nil else { throw Self.storageError }
        var canonical = draft
        canonical.remoteID = canonical.remoteID ?? "draft-\(draft.id)"
        canonical.scheduledFor = scheduledFor
        let attachments = try Self.journalAttachments(for: canonical, in: mailboxData)
        let sender = try sender(mailboxID: mailboxID)
        let parent = canonical.inReplyToMessageID.flatMap { parentID in
            mailboxData.messagesByFolder.values.flatMap(\.self).first { $0.id == parentID }
        }
        let parentMessageID = parent?.rfcMessageID
        let references = Self.deduplicatedReferences((parent?.references ?? []) + [parentMessageID].compactMap { $0 })
        let draftsFolderID = Self.ensureDraftsFolderID(in: &mailboxData)
        let existed = mailboxData.savedDrafts[canonical.id] != nil
        Self.projectDraft(canonical, folderID: draftsFolderID, sender: sender, at: now(), in: &mailboxData)
        let update: (MockSendJournalRecord, Bool)
        do {
            update = try transactJournal { records in
                if let delivered = records.last(where: {
                    $0.sourceID.mailboxID == mailboxID && $0.draftID == canonical.id && $0.state == .delivered
                }) {
                    return (delivered, false)
                }
                if let index = records.lastIndex(where: {
                    $0.sourceID.mailboxID == mailboxID && $0.draftID == canonical.id && $0.state == .queued
                }) {
                    let record = records[index]
                    var updated = record
                    if updated.draft != canonical { updated.draftProjectionDate = now() }
                    updated.draft = canonical
                    updated.attachments = attachments
                    updated.scheduledFor = scheduledFor
                    updated.sender = sender
                    updated.parentMessageID = parentMessageID
                    updated.references = references
                    records[index] = updated
                    return (updated, updated != record)
                }
                if let index = records.lastIndex(where: {
                    $0.sourceID.mailboxID == mailboxID && $0.draftID == canonical.id && $0.state == .canceled
                }) {
                    var updated = records[index]
                    updated.scheduleID = UUID().uuidString
                    if updated.draft != canonical || updated.draftProjectionDate == nil {
                        updated.draftProjectionDate = now()
                    }
                    updated.draft = canonical
                    updated.attachments = attachments
                    updated.state = .queued
                    updated.scheduledFor = scheduledFor
                    updated.sender = sender
                    updated.parentMessageID = parentMessageID
                    updated.references = references
                    updated.nextAttemptAt = nil
                    records[index] = updated
                    return (updated, true)
                }
                let record = MockSendJournalRecord(
                    recordID: UUID().uuidString,
                    accountID: accountID,
                    sourceID: MailSourceID(accountID: accountID, mailboxID: mailboxID),
                    draftID: canonical.id,
                    scheduleID: UUID().uuidString,
                    draft: canonical,
                    attachments: attachments,
                    state: .queued,
                    scheduledFor: scheduledFor,
                    sentHeader: nil,
                    sentBody: nil,
                    nextAttemptAt: nil,
                    sender: sender,
                    parentMessageID: parentMessageID,
                    references: references,
                    draftProjectionDate: now()
                )
                records.append(record)
                return (record, true)
            }
        } catch { throw Self.storageError }
        if update.0.state == .delivered {
            return SendResult(sentMessageID: update.0.sentHeader?.id)
        }
        guard update.1 else { return SendResult(sentMessageID: nil, scheduledFor: update.0.scheduledFor) }
        if journal == nil { dataByMailboxID[mailboxID] = mailboxData }
        refreshScheduledSnapshot()
        emit(existed ? .messagesUpdated(folderID: draftsFolderID, messageIDs: [canonical.remoteID!]) : .messagesAdded(
            folderID: draftsFolderID,
            messageIDs: [canonical.remoteID!]
        ))
        emit(.outboxChanged)
        return SendResult(sentMessageID: nil, scheduledFor: update.0.scheduledFor)
    }

    func cancelScheduledSend(id: String) throws -> Draft? {
        try ensureActive()
        try reloadJournalRecords()
        guard let record = journalRecords.first(where: { $0.scheduleID == id && $0.state == .queued }),
              var draft = record.draft,
              var mailboxData = dataByMailboxID[record.sourceID.mailboxID] else {
            throw ScheduledSendEditingError.notFound
        }
        draft.scheduledFor = nil
        let folderID = Self.ensureDraftsFolderID(in: &mailboxData)
        try Self.projectDraft(
            draft,
            folderID: folderID,
            sender: sender(mailboxID: record.sourceID.mailboxID),
            at: now(),
            in: &mailboxData
        )
        _ = try transactJournal { records in
            guard let index = records.firstIndex(where: {
                $0.recordID == record.recordID && $0.scheduleID == id && $0.state == .queued
                    && $0.sourceID == record.sourceID && $0.draft == record.draft
                    && $0.scheduledFor == record.scheduledFor
            }) else {
                throw ScheduledSendEditingError.notFound
            }
            records[index].state = .canceled
            records[index].draftProjectionDate = now()
            records[index].draft = draft
            records[index].scheduledFor = nil
            records[index].scheduleID = nil
            return ()
        }
        if journal == nil { dataByMailboxID[record.sourceID.mailboxID] = mailboxData }
        refreshScheduledSnapshot()
        emit(.messagesUpdated(folderID: folderID, messageIDs: [draft.remoteID ?? "draft-\(draft.id)"]))
        emit(.outboxChanged)
        return draft
    }

    func rescheduleSend(id: String, for date: Date) throws {
        guard date.timeIntervalSince1970.isFinite else { throw ScheduledSendEditingError.invalidDate }
        try ensureActive()
        try reloadJournalRecords()
        guard let record = journalRecords.first(where: { $0.scheduleID == id && $0.state == .queued }),
              var draft = record.draft,
              var mailboxData = dataByMailboxID[record.sourceID.mailboxID] else {
            throw ScheduledSendEditingError.notFound
        }
        guard record.scheduledFor != date else { return }
        draft.scheduledFor = date
        let folderID = Self.ensureDraftsFolderID(in: &mailboxData)
        try Self.projectDraft(
            draft,
            folderID: folderID,
            sender: sender(mailboxID: record.sourceID.mailboxID),
            at: now(),
            in: &mailboxData
        )
        _ = try transactJournal { records in
            guard let index = records.firstIndex(where: {
                $0.recordID == record.recordID && $0.scheduleID == id && $0.state == .queued
                    && $0.sourceID == record.sourceID && $0.draft == record.draft
                    && $0.scheduledFor == record.scheduledFor
            }) else {
                throw ScheduledSendEditingError.notFound
            }
            records[index].draft = draft
            records[index].draftProjectionDate = now()
            records[index].scheduledFor = date
            records[index].nextAttemptAt = nil
            return ()
        }
        if journal == nil { dataByMailboxID[record.sourceID.mailboxID] = mailboxData }
        refreshScheduledSnapshot()
        emit(.messagesUpdated(folderID: folderID, messageIDs: [draft.remoteID ?? "draft-\(draft.id)"]))
        emit(.outboxChanged)
    }

    func deliverDueScheduledSends() {
        do { try reloadJournalRecords() } catch { return }
        guard journalLoadError == nil, !isPaused else { return }
        let date = now()
        let dueRecords = journalRecords.filter {
            $0.state == .queued && ($0.scheduledFor ?? .distantFuture) <= date
                && ($0.nextAttemptAt ?? retryAfter[$0.recordID] ?? .distantPast) <= date
        }
        for record in dueRecords {
            guard let draft = record.draft,
                  dataByMailboxID[record.sourceID.mailboxID] != nil else { continue }
            guard journalRecords.contains(where: { $0.recordID == record.recordID && $0.state == .queued }) else { continue }
            do {
                guard !isPaused,
                      let currentRecord = journalRecords.first(where: { $0.recordID == record.recordID && $0.state == .queued }),
                      let currentDraft = currentRecord.draft,
                      currentDraft == draft,
                      (currentRecord.scheduledFor ?? .distantFuture) <= date,
                      (currentRecord.nextAttemptAt ?? retryAfter[record.recordID] ?? .distantPast) <= date else { continue }
                _ = try send(
                    draft: currentDraft,
                    mailboxID: record.sourceID.mailboxID,
                    scheduledDelivery: (
                        recordID: record.recordID,
                        scheduleID: record.scheduleID ?? "",
                        at: date,
                        sender: record.sender ?? sender(mailboxID: record.sourceID.mailboxID),
                        parentMessageID: record.parentMessageID,
                        references: record.references ?? []
                    )
                )
            } catch ScheduledSendEditingError.notFound {
                continue
            } catch {
                retryAfter[record.recordID] = date.addingTimeInterval(60)
                do {
                    _ = try transactJournal { records in
                        guard let index = records.firstIndex(where: { $0.recordID == record.recordID }) else { return () }
                        records[index].nextAttemptAt = date.addingTimeInterval(60)
                        return ()
                    }
                    refreshScheduledSnapshot()
                } catch {}
            }
        }
    }

    private static var storageError: ScheduledSendEditingError {
        .stagingUnavailable
    }

    private func transactJournal<T>(
        _ operation: (inout [MockSendJournalRecord]) throws -> T
    ) throws -> T {
        if let journal {
            do {
                let previousRecords = journalRecords
                let transaction = try journal.transact(operation)
                dataByMailboxID = Self.projectJournalChanges(
                    previousRecords: previousRecords,
                    records: transaction.records,
                    mailboxes: mailboxes,
                    current: dataByMailboxID
                )
                journalRecords = transaction.records
                journalLoadError = nil
                refreshScheduledSnapshot()
                return transaction.value
            } catch let error as ScheduledSendEditingError {
                throw error
            } catch {
                journalLoadError = error
                throw Self.storageError
            }
        }
        let value = try operation(&journalRecords)
        refreshScheduledSnapshot()
        return value
    }

    private func reloadJournalRecords() throws {
        guard let journal else { return }
        do {
            let records = try journal.load()
            dataByMailboxID = Self.projectJournalChanges(
                previousRecords: journalRecords,
                records: records,
                mailboxes: mailboxes,
                current: dataByMailboxID
            )
            journalRecords = records
            journalLoadError = nil
            refreshScheduledSnapshot()
        } catch {
            journalLoadError = error
            throw Self.storageError
        }
    }

    private func refreshScheduledSnapshot() {
        scheduledSendSnapshot.replace(with: Self.scheduledEntries(from: journalRecords))
    }

    private static func scheduledEntries(from records: [MockSendJournalRecord]) -> [PendingScheduledSend] {
        records.compactMap { record -> PendingScheduledSend? in
            guard record.state == .queued, let date = record.scheduledFor, let draft = record.draft,
                  let id = record.scheduleID else { return nil }
            return PendingScheduledSend(
                draftID: draft.id,
                scheduledFor: date,
                id: id,
                sourceID: record.sourceID,
                subject: draft.subject,
                state: .waiting,
                lastError: nil,
                nextAttemptAt: record.nextAttemptAt
            )
        }.sorted { $0.scheduledFor < $1.scheduledFor }
    }

    func purgePersistentState() throws {
        stopWorker()
        try journal?.purge()
        isPaused = true
        isPurged = true
        retryAfter.removeAll()
        dataByMailboxID = initialDataByMailboxID
        journalRecords = []
        journalLoadError = nil
        refreshScheduledSnapshot()
    }

    private static func journalAttachments(
        for draft: Draft,
        in data: MockMailboxData
    ) throws -> [MockSendJournalAttachment] {
        try draft.attachmentIDs.map { id in
            guard let ownerID = data.attachmentDraftIDs[id],
                  ownerID == draft.id || ownerID == draft.remoteID,
                  let metadata = data.attachmentsByID[id],
                  let bytes = data.attachmentDataByID[id] else {
                throw MailBackendError.notFound(id: id)
            }
            return MockSendJournalAttachment(metadata: metadata, data: bytes, draftID: draft.id)
        }
    }

    private static func projectDraft(
        _ draft: Draft,
        folderID: String,
        sender: Correspondent,
        at date: Date,
        in data: inout MockMailboxData
    ) {
        let remoteID = draft.remoteID ?? "draft-\(draft.id)"
        data.savedDrafts[draft.id] = draft
        data.messagesByFolder[folderID, default: []].removeAll { $0.id == remoteID }
        data.messagesByFolder[folderID, default: []].append(MessageHeader(
            id: remoteID,
            threadID: threadID(for: draft, in: data) ?? draft.threadID ?? remoteID,
            folderID: folderID,
            from: sender,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            snippet: snippet(from: draft.htmlBody),
            date: date,
            isRead: true,
            hasAttachments: !draft.attachmentIDs.isEmpty
        ))
        data.messageBodies[remoteID] = MessageBody(
            messageID: remoteID,
            html: draft.htmlBody,
            plainText: HTMLTextStripper.plainText(from: draft.htmlBody),
            attachments: attachments(for: draft.attachmentIDs, in: data)
        )
    }

    private static func projectJournalChanges(
        previousRecords: [MockSendJournalRecord],
        records: [MockSendJournalRecord],
        mailboxes: [Mailbox],
        current: [Mailbox.ID: MockMailboxData]
    ) -> [Mailbox.ID: MockMailboxData] {
        var result = current
        let previousByID = Dictionary(uniqueKeysWithValues: previousRecords.map { ($0.recordID, $0) })
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.recordID, $0) })
        for previous in previousRecords {
            let changed = recordsByID[previous.recordID].map { !hasSameJournalProjection(previous, $0) } ?? true
            guard changed else { continue }
            guard var data = result[previous.sourceID.mailboxID] else { continue }
            removeJournalProjection(of: previous, keeping: records, in: &data)
            result[previous.sourceID.mailboxID] = data
        }
        for record in records {
            let changed = previousByID[record.recordID].map { !hasSameJournalProjection($0, record) } ?? true
            guard changed else { continue }
            let mailboxID = record.sourceID.mailboxID
            guard var data = result[mailboxID] else { continue }
            projectJournalRecord(record, mailboxes: mailboxes, in: &data)
            result[mailboxID] = data
        }
        return result
    }

    private static func hasSameJournalProjection(
        _ lhs: MockSendJournalRecord,
        _ rhs: MockSendJournalRecord
    ) -> Bool {
        lhs.sourceID == rhs.sourceID && lhs.draftID == rhs.draftID && lhs.draft == rhs.draft
            && lhs.attachments == rhs.attachments && lhs.state == rhs.state
            && lhs.draftProjectionDate == rhs.draftProjectionDate && lhs.sentHeader == rhs.sentHeader
            && lhs.sentBody == rhs.sentBody && lhs.sender == rhs.sender
            && lhs.parentMessageID == rhs.parentMessageID && lhs.references == rhs.references
    }

    private static func removeJournalProjection(
        of record: MockSendJournalRecord,
        keeping records: [MockSendJournalRecord],
        in data: inout MockMailboxData
    ) {
        if record.state != .delivered {
            _ = removeDraft(draftID: record.draftID, in: &data)
            data.savedDrafts[record.draftID] = nil
        }
        let retainedAttachmentIDs = Set(records.filter { $0.sourceID == record.sourceID }
            .flatMap { $0.attachments.map { $0.metadata.id } })
        for attachment in record.attachments where !retainedAttachmentIDs.contains(attachment.metadata.id) {
            let id = attachment.metadata.id
            guard data.attachmentDraftIDs[id] == record.draftID else { continue }
            data.attachmentsByID[id] = nil
            data.attachmentDataByID[id] = nil
            data.attachmentDraftIDs[id] = nil
        }
    }

    private static func projectJournalRecord(
        _ record: MockSendJournalRecord,
        mailboxes: [Mailbox],
        in data: inout MockMailboxData
    ) {
        let mailboxID = record.sourceID.mailboxID
        for attachment in record.attachments {
            data.attachmentsByID[attachment.metadata.id] = attachment.metadata
            data.attachmentDataByID[attachment.metadata.id] = attachment.data
            data.attachmentDraftIDs[attachment.metadata.id] = attachment.draftID
        }
        switch record.state {
        case .queued, .canceled:
            if let draft = record.draft, let projectionDate = record.draftProjectionDate {
                let folderID = ensureDraftsFolderID(in: &data)
                let sender = record.sender ?? mailboxes.first(where: { $0.id == mailboxID }).map {
                    Correspondent(name: $0.displayName, email: $0.email)
                } ?? Correspondent(email: "mock@example.test")
                projectDraft(draft, folderID: folderID, sender: sender, at: projectionDate, in: &data)
            } else {
                _ = removeDraft(draftID: record.draftID, in: &data)
                data.savedDrafts[record.draftID] = nil
            }
        case .delivered:
            _ = removeDraft(draftID: record.draftID, in: &data)
            data.savedDrafts[record.draftID] = nil
            if let header = record.sentHeader, let body = record.sentBody {
                if !data.folders.contains(where: { $0.id == header.folderID }) {
                    data.folders.append(Folder(id: header.folderID, name: "Sent", role: .sent))
                }
                data.messagesByFolder[header.folderID, default: []].removeAll { $0.id == header.id }
                data.messagesByFolder[header.folderID, default: []].append(header)
                data.messageBodies[header.id] = body
                if let replyID = record.draft?.inReplyToMessageID {
                    updateHeader(id: replyID, in: &data) { $0.isAnswered = true }
                }
                if let forwardedID = record.draft?.forwardedMessageID {
                    updateHeader(id: forwardedID, in: &data) { $0.isForwarded = true }
                }
            }
        }
    }

    var allMessages: [MessageHeader] {
        (try? allMessages(in: activeMailboxID)) ?? []
    }

    private var activeData: MockMailboxData {
        (try? data(mailboxID: activeMailboxID)) ?? MockMailboxData(folders: [], messagesByFolder: [:])
    }

    private func updateActiveData<T>(_ body: (inout MockMailboxData) -> T) -> T {
        do {
            return try updateData(mailboxID: activeMailboxID, body)
        } catch {
            preconditionFailure("Active mailbox data is missing: \(error)")
        }
    }

    func hasMailbox(id: Mailbox.ID) -> Bool {
        mailboxes.contains { $0.id == id }
    }

    func allMessages(in mailboxID: Mailbox.ID) throws -> [MessageHeader] {
        try data(mailboxID: mailboxID).messagesByFolder.values.flatMap(\.self)
    }

    private func data(mailboxID: Mailbox.ID) throws -> MockMailboxData {
        guard let data = dataByMailboxID[mailboxID] else {
            throw MailBackendError.notFound(id: mailboxID)
        }
        return data
    }

    private func updateData<T>(
        mailboxID: Mailbox.ID,
        _ body: (inout MockMailboxData) -> T
    ) throws -> T {
        var data = try data(mailboxID: mailboxID)
        let result = body(&data)
        dataByMailboxID[mailboxID] = data
        return result
    }

    func mailboxSnapshots() -> [Mailbox] {
        mailboxes
    }

    func currentMailbox() throws -> Mailbox {
        guard let mailbox = mailboxes.first(where: { $0.id == activeMailboxID }) else {
            throw MailBackendError.notConnected
        }
        return mailbox
    }

    private func activeSender() throws -> Correspondent {
        let mailbox = try currentMailbox()
        return Correspondent(name: mailbox.displayName, email: mailbox.email)
    }

    private func sender(mailboxID: Mailbox.ID) throws -> Correspondent {
        guard let mailbox = mailboxes.first(where: { $0.id == mailboxID }) else {
            throw MailBackendError.notFound(id: mailboxID)
        }
        return Correspondent(name: mailbox.displayName, email: mailbox.email)
    }

    func switchMailbox(id: Mailbox.ID) throws {
        guard mailboxes.contains(where: { $0.id == id }) else {
            throw MailBackendError.notFound(id: id)
        }
        activeMailboxID = id
        emit(.mailboxChanged(mailboxID: id))
    }

    func messages(in folderID: String) throws -> [MessageHeader] {
        try messages(in: folderID, mailboxID: activeMailboxID)
    }

    func messages(in folderID: String, mailboxID: Mailbox.ID) throws -> [MessageHeader] {
        try reloadJournalRecords()
        return try (data(mailboxID: mailboxID).messagesByFolder[folderID] ?? [])
            .sorted { $0.date > $1.date }
    }

    func folderSnapshots() throws -> [Folder] {
        try folderSnapshots(mailboxID: activeMailboxID)
    }

    func folderSnapshots(mailboxID: Mailbox.ID) throws -> [Folder] {
        try reloadJournalRecords()
        let data = try data(mailboxID: mailboxID)
        return data.folders.map { folder in
            let messages = data.messagesByFolder[folder.id] ?? []
            return Folder(
                id: folder.id,
                name: folder.name,
                role: folder.role,
                parentID: folder.parentID,
                unreadCount: messages.filter { !$0.isRead }.count,
                totalCount: messages.count
            )
        }
    }

    /// Returns the spam/junk folder ID for the active mailbox, or `nil` if absent.
    func spamFolderID() -> Folder.ID? {
        activeData.folders.first { $0.role == .spam }?.id
    }

    /// Returns the inbox folder ID for the active mailbox.
    func inboxFolderID() -> Folder.ID {
        activeData.folders.first { $0.role == .inbox }?.id ?? "inbox"
    }

    /// Records an email address in the blocked-senders set.
    func addBlockedSender(_ email: String) {
        blockedSenders.insert(email.lowercased())
    }

    func createFolder(name: String, parentID: Folder.ID?) -> Folder {
        (try? createFolder(name: name, parentID: parentID, mailboxID: activeMailboxID))
            ?? Folder(id: "new-folder", name: name, role: .custom, parentID: parentID)
    }

    func createFolder(
        name: String,
        parentID: Folder.ID?,
        mailboxID: Mailbox.ID
    ) throws -> Folder {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MailBackendError.backendSpecific(message: "Folder name can't be empty.")
        }

        let snapshot = try data(mailboxID: mailboxID)
        if let parentID {
            guard snapshot.folders.contains(where: { $0.id == parentID }) else {
                throw MailBackendError.notFound(id: parentID)
            }
        }

        let folderID = Self.uniqueFolderID(
            base: Self.slug(from: trimmedName),
            existingIDs: Set(snapshot.folders.map(\.id))
        )
        let created = Folder(
            id: folderID,
            name: trimmedName,
            role: .custom,
            parentID: parentID
        )
        try updateData(mailboxID: mailboxID) { data in
            data.folders.append(created)
            data.messagesByFolder[folderID] = data.messagesByFolder[folderID] ?? []
        }
        emit(.folderRefreshed(folderID: folderID))
        return created
    }

    func importMessages(_ messages: [ImportedMessage], into folderID: Folder.ID) throws -> MailImportSummary {
        try importMessages(messages, into: folderID, mailboxID: activeMailboxID)
    }

    func importMessages(
        _ messages: [ImportedMessage],
        into folderID: Folder.ID,
        mailboxID: Mailbox.ID
    ) throws -> MailImportSummary {
        let snapshot = try data(mailboxID: mailboxID)
        guard snapshot.folders.contains(where: { $0.id == folderID }) else {
            throw MailBackendError.notFound(id: folderID)
        }

        var errors: [String] = []
        var importedCount = 0
        try updateData(mailboxID: mailboxID) { data in
            let existingIDs = Set(data.messagesByFolder.values.flatMap { $0.map(\.id) })
            for (index, message) in messages.enumerated() {
                let converted = Self.convertImportedMessage(
                    message,
                    folderID: folderID,
                    index: index,
                    existingIDs: existingIDs.union(data.messagesByFolder[folderID, default: []].map(\.id))
                )
                guard let converted else {
                    errors.append("Message \(index + 1) could not be imported.")
                    continue
                }
                data.messagesByFolder[folderID, default: []].append(converted.header)
                data.messageBodies[converted.header.id] = converted.body
                importedCount += 1
            }
        }
        emit(.folderRefreshed(folderID: folderID))
        return MailImportSummary(importedCount: importedCount, errors: errors)
    }

    func renameFolder(id: Folder.ID, name: String) throws -> Folder {
        try renameFolder(id: id, name: name, mailboxID: activeMailboxID)
    }

    func renameFolder(
        id: Folder.ID,
        name: String,
        mailboxID: Mailbox.ID
    ) throws -> Folder {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MailBackendError.backendSpecific(message: "Folder name can't be empty.")
        }

        let current = try folder(id: id, mailboxID: mailboxID)
        guard current.role == .custom else {
            throw MailBackendError.backendSpecific(message: "Only custom folders can be renamed.")
        }

        let renamed = try updateData(mailboxID: mailboxID) { data -> Folder in
            guard let index = data.folders.firstIndex(where: { $0.id == id }) else {
                return current
            }
            let updated = Folder(
                id: current.id,
                name: trimmedName,
                role: current.role,
                parentID: current.parentID
            )
            data.folders[index] = updated
            return updated
        }
        emit(.folderRefreshed(folderID: id))
        return renamed
    }

    func deleteFolder(id: Folder.ID) throws {
        try deleteFolder(id: id, mailboxID: activeMailboxID)
    }

    func deleteFolder(id: Folder.ID, mailboxID: Mailbox.ID) throws {
        let root = try folder(id: id, mailboxID: mailboxID)
        guard root.role == .custom else {
            throw MailBackendError.backendSpecific(message: "Only custom folders can be deleted.")
        }

        let idsToDelete = try folderSubtreeIDs(rootID: id, mailboxID: mailboxID)
        try updateData(mailboxID: mailboxID) { data in
            data.folders.removeAll { idsToDelete.contains($0.id) }
            let removedMessageIDs = Set(idsToDelete.flatMap { data.messagesByFolder[$0]?.map(\.id) ?? [] })
            for folderID in idsToDelete {
                data.messagesByFolder.removeValue(forKey: folderID)
            }
            for messageID in removedMessageIDs {
                data.messageBodies.removeValue(forKey: messageID)
            }
        }
        emit(.folderRefreshed(folderID: id))
    }

    func flushFolder(id: Folder.ID) throws {
        try flushFolder(id: id, mailboxID: activeMailboxID)
    }

    func flushFolder(id: Folder.ID, mailboxID: Mailbox.ID) throws {
        _ = try folder(id: id, mailboxID: mailboxID)
        let removedIDs = try updateData(mailboxID: mailboxID) { data -> [MessageHeader.ID] in
            let removed = data.messagesByFolder[id]?.map(\.id) ?? []
            data.messagesByFolder[id] = []
            for messageID in removed {
                data.messageBodies.removeValue(forKey: messageID)
            }
            return removed
        }
        if !removedIDs.isEmpty {
            emit(.messagesRemoved(folderID: id, messageIDs: removedIDs))
        }
        emit(.folderRefreshed(folderID: id))
    }

    func body(for messageID: String) -> MessageBody {
        (try? body(for: messageID, mailboxID: activeMailboxID)) ?? Self.previewBodyFallback(for: messageID)
    }

    func body(for messageID: String, mailboxID: Mailbox.ID) throws -> MessageBody {
        try data(mailboxID: mailboxID).messageBodies[messageID]
            ?? Self.previewBodyFallback(for: messageID)
    }

    func rawMessageSource(for messageID: String) -> String {
        (try? rawMessageSource(for: messageID, mailboxID: activeMailboxID))
            ?? Self.previewRawMessageSource(for: body(for: messageID))
    }

    func rawMessageSource(for messageID: String, mailboxID: Mailbox.ID) throws -> String {
        let body = try body(for: messageID, mailboxID: mailboxID)
        return Self.previewRawMessageSource(for: body)
    }

    private static func previewBodyFallback(for messageID: String) -> MessageBody {
        MessageBody(
            messageID: messageID,
            html: "<p>Hi team,</p><p>Thanks for the update. The plan looks good from my side.</p><p>I will share any final changes before our next check-in.</p><p>Best regards</p>",
            plainText: "Hi team,\n\nThanks for the update. The plan looks good from my side.\n\nI will share any final changes before our next check-in.\n\nBest regards",
            attachments: [],
            listUnsubscribe: previewListUnsubscribe(for: messageID)
        )
    }

    private static func previewListUnsubscribe(for messageID: String) -> ListUnsubscribeOptions? {
        if messageID == "m7" {
            return ListUnsubscribeOptions.parse(
                listUnsubscribe: "<https://news.example.org/unsubscribe>, <mailto:unsubscribe@news.example.org>",
                listUnsubscribePost: nil
            )
        }
        if messageID == "newsletter-1" || messageID.hasSuffix("-inbox-5") {
            return ListUnsubscribeOptions.parse(
                listUnsubscribe: "<https://coastal-post.example/unsubscribe/one-click>, <mailto:unsubscribe@coastal-post.example>",
                listUnsubscribePost: "List-Unsubscribe=One-Click"
            )
        }
        return nil
    }

    private static func previewRawMessageSource(for body: MessageBody) -> String {
        // Label the content type after whichever part is actually emitted
        // (plain text is preferred) so the header and body never disagree.
        let bodyText: String
        let contentType: String
        if let plainText = body.plainText {
            bodyText = plainText
            contentType = "text/plain; charset=utf-8"
        } else if let html = body.html {
            bodyText = html
            contentType = "text/html; charset=utf-8"
        } else {
            bodyText = ""
            contentType = "text/plain; charset=utf-8"
        }
        return [
            "Message-ID: <\(body.messageID)@mock.brev>",
            "Content-Type: \(contentType)",
            "",
            bodyText,
        ].joined(separator: "\r\n")
    }

    private static func convertImportedMessage(
        _ message: ImportedMessage,
        folderID: Folder.ID,
        index: Int,
        existingIDs: Set<String>
    ) -> (header: MessageHeader, body: MessageBody)? {
        let bodyText = String(data: message.bodyData, encoding: .utf8)
            ?? String(data: message.bodyData, encoding: .isoLatin1)
            ?? ""
        let fallbackID = "imported-\(index + 1)"
        let id = uniqueMessageID(
            base: sanitizedMessageID(message.messageID) ?? fallbackID,
            existingIDs: existingIDs
        )
        let subject = nonEmpty(message.subject) ?? "(No subject)"
        let from = parseCorrespondent(message.from) ?? Correspondent(email: "unknown@example.invalid")
        let to = parseCorrespondents(message.header("To"))
        let cc = parseCorrespondents(message.header("Cc"))
        let date = parseHeaderDate(message.date) ?? Date()
        let snippet = bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let header = MessageHeader(
            id: id,
            threadID: id,
            folderID: folderID,
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            snippet: String(snippet.prefix(160)),
            date: date,
            isRead: true,
            hasAttachments: false
        )
        let body = MessageBody(
            messageID: id,
            plainText: bodyText,
            attachments: []
        )
        return (header, body)
    }

    private static func uniqueMessageID(base: String, existingIDs: Set<String>) -> String {
        var candidate = base
        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedMessageID(_ raw: String?) -> String? {
        guard let value = nonEmpty(raw) else { return nil }
        let stripped = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_@."))
        let scalars = stripped.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func parseCorrespondents(_ raw: String?) -> [Correspondent] {
        guard let raw = nonEmpty(raw) else { return [] }
        return raw.split(separator: ",").compactMap { parseCorrespondent(String($0)) }
    }

    private static func parseCorrespondent(_ raw: String?) -> Correspondent? {
        guard let raw = nonEmpty(raw) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.lastIndex(of: "<"),
           let close = trimmed.lastIndex(of: ">"),
           open < close {
            let name = trimmed[..<open]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
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
        guard let raw = nonEmpty(raw) else { return nil }
        for formatter in importDateFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static let importDateFormatters: [DateFormatter] = [
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

    func downloadAttachment(_ attachment: Attachment) throws -> Data {
        try downloadAttachment(attachment, mailboxID: activeMailboxID)
    }

    func downloadAttachment(_ attachment: Attachment, mailboxID: Mailbox.ID) throws -> Data {
        let id = attachment.resource ?? attachment.id
        guard let data = try data(mailboxID: mailboxID).attachmentDataByID[id] else {
            throw MailBackendError.notFound(id: attachment.id)
        }
        return data
    }

    func mutate(ids: [String], _ transform: (inout MessageHeader) -> Void) {
        try? mutate(ids: ids, mailboxID: activeMailboxID, transform)
    }

    func mutate(
        ids: [String],
        mailboxID: Mailbox.ID,
        _ transform: (inout MessageHeader) -> Void
    ) throws {
        let idSet = Set(ids)
        let events = try updateData(mailboxID: mailboxID) { data in
            for key in data.messagesByFolder.keys {
                data.messagesByFolder[key] = data.messagesByFolder[key]?.map { msg in
                    guard idSet.contains(msg.id) else { return msg }
                    var copy = msg
                    transform(&copy)
                    return copy
                }
            }
            var byFolder: [String: [String]] = [:]
            for (folderID, list) in data.messagesByFolder {
                let hits = list.filter { idSet.contains($0.id) }.map(\.id)
                if !hits.isEmpty { byFolder[folderID] = hits }
            }
            return byFolder.map { folderID, hits in
                MailEvent.messagesUpdated(folderID: folderID, messageIDs: hits)
            }
        }
        for event in events {
            emit(event)
        }
    }

    func move(ids: [String], to destinationFolderID: String) {
        try? move(ids: ids, to: destinationFolderID, mailboxID: activeMailboxID)
    }

    func move(ids: [String], to destinationFolderID: String, mailboxID: Mailbox.ID) throws {
        let idSet = Set(ids)
        let events = try updateData(mailboxID: mailboxID) { data in
            var events: [MailEvent] = []
            var moved: [MessageHeader] = []
            for key in data.messagesByFolder.keys {
                let (kept, gone) = (data.messagesByFolder[key] ?? []).reduce(into: (
                    [MessageHeader](),
                    [MessageHeader]()
                )) { acc, msg in
                    if idSet.contains(msg.id) {
                        acc.1.append(msg)
                    } else {
                        acc.0.append(msg)
                    }
                }
                data.messagesByFolder[key] = kept
                if !gone.isEmpty {
                    events.append(.messagesRemoved(folderID: key, messageIDs: gone.map(\.id)))
                    moved.append(contentsOf: gone.map { Self.copy($0, folderID: destinationFolderID) })
                }
            }
            if !moved.isEmpty {
                data.messagesByFolder[destinationFolderID, default: []].append(contentsOf: moved)
                events.append(.messagesAdded(folderID: destinationFolderID, messageIDs: moved.map(\.id)))
            }
            return events
        }
        for event in events {
            emit(event)
        }
    }

    func copy(ids: [String], to destinationFolderID: String) {
        try? copy(ids: ids, to: destinationFolderID, mailboxID: activeMailboxID)
    }

    func copy(ids: [String], to destinationFolderID: String, mailboxID: Mailbox.ID) throws {
        let idSet = Set(ids)
        let events = try updateData(mailboxID: mailboxID) { data in
            let noEvents: [MailEvent] = []
            // Don't re-append a message that already exists in the destination,
            // so a repeated copy can't create duplicate IDs in one folder.
            let existingDestinationIDs = Set((data.messagesByFolder[destinationFolderID] ?? []).map(\.id))
            let copied = data.messagesByFolder.values
                .flatMap(\.self)
                .filter { idSet.contains($0.id) && $0.folderID != destinationFolderID }
                .map { Self.copy($0, folderID: destinationFolderID) }
                .filter { !existingDestinationIDs.contains($0.id) }
            guard !copied.isEmpty else { return noEvents }
            data.messagesByFolder[destinationFolderID, default: []].append(contentsOf: copied)
            return [.messagesAdded(folderID: destinationFolderID, messageIDs: copied.map(\.id))]
        }
        for event in events {
            emit(event)
        }
    }

    func delete(ids: [String]) {
        try? delete(ids: ids, mailboxID: activeMailboxID)
    }

    func delete(ids: [String], mailboxID: Mailbox.ID) throws {
        let idSet = Set(ids)
        let events = try updateData(mailboxID: mailboxID) { data in
            var events: [MailEvent] = []
            let trashFolderID = Self.ensureTrashFolderID(in: &data)
            let originalTrashMessages = data.messagesByFolder[trashFolderID] ?? []
            let sourceFolderIDs = Array(data.messagesByFolder.keys)
            for key in sourceFolderIDs where key != trashFolderID {
                let existing = data.messagesByFolder[key] ?? []
                let removedMessages = existing.filter { idSet.contains($0.id) }
                guard !removedMessages.isEmpty else { continue }
                data.messagesByFolder[key] = existing.filter { !idSet.contains($0.id) }
                let removedIDs = removedMessages.map(\.id)
                events.append(.messagesRemoved(folderID: key, messageIDs: removedIDs))

                let moved = removedMessages.map {
                    Self.copy($0, folderID: trashFolderID)
                }
                data.messagesByFolder[trashFolderID, default: []].append(contentsOf: moved)
                events.append(.messagesAdded(folderID: trashFolderID, messageIDs: removedIDs))
            }

            let permanentlyRemoved = originalTrashMessages.map(\.id).filter(idSet.contains)
            if !permanentlyRemoved.isEmpty {
                let permanentlyRemovedSet = Set(permanentlyRemoved)
                data.messagesByFolder[trashFolderID] = (data.messagesByFolder[trashFolderID] ?? [])
                    .filter { !permanentlyRemovedSet.contains($0.id) }
                for messageID in permanentlyRemoved {
                    data.messageBodies[messageID] = nil
                }
                events.append(.messagesRemoved(folderID: trashFolderID, messageIDs: permanentlyRemoved))
            }
            return events
        }
        for event in events {
            emit(event)
        }
    }

    func replyToCalendarInvite(messageID: String, response: AttendeeState) throws {
        try replyToCalendarInvite(
            messageID: messageID,
            response: response,
            mailboxID: activeMailboxID
        )
    }

    func replyToCalendarInvite(
        messageID: String,
        response: AttendeeState,
        mailboxID: Mailbox.ID
    ) throws {
        let event = try updateData(mailboxID: mailboxID) { data -> MailEvent? in
            for folderID in data.messagesByFolder.keys {
                guard let index = data.messagesByFolder[folderID]?.firstIndex(where: { $0.id == messageID }) else {
                    continue
                }
                data.messagesByFolder[folderID]?[index].isAnswered = response != .needsAction
                return .messagesUpdated(folderID: folderID, messageIDs: [messageID])
            }
            return nil
        }
        guard let event else {
            throw MailBackendError.notFound(id: messageID)
        }
        emit(event)
    }

    func vacationResponderSettings(mailboxID: Mailbox.ID) throws -> [VacationResponderSettings] {
        try data(mailboxID: mailboxID).vacationResponders
    }

    func saveVacationResponder(
        _ draft: VacationResponderDraft,
        mailboxID: Mailbox.ID
    ) throws -> VacationResponderSettings {
        let slug = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let id = draft.id ?? (slug.isEmpty ? "vacation-responder" : slug)
        let responder = VacationResponderSettings(
            id: id,
            name: draft.name,
            isEnabled: draft.isEnabled,
            message: draft.message,
            schedule: VacationResponderSchedule(
                startsAt: draft.startsAt,
                endsAt: draft.endsAt,
                recurrence: draft.recurrence
            ),
            excludedRecipients: draft.excludedRecipients,
            replyFrom: draft.replyFrom
        )
        try updateData(mailboxID: mailboxID) { data in
            data.vacationResponders.removeAll { $0.id == responder.id }
            data.vacationResponders.append(responder)
        }
        return responder
    }

    func deleteVacationResponder(id: String, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.vacationResponders.removeAll { $0.id == id }
        }
    }

    func resetVacationResponderCounter(id: String, mailboxID: Mailbox.ID) throws {
        guard try data(mailboxID: mailboxID).vacationResponders.contains(where: { $0.id == id }) else {
            throw MailBackendError.notFound(id: id)
        }
    }

    func serverRules(mailboxID: Mailbox.ID) throws -> [ServerRule] {
        try data(mailboxID: mailboxID).serverRules
    }

    func saveServerRule(_ rule: ServerRule, mailboxID: Mailbox.ID) throws -> ServerRule {
        try updateData(mailboxID: mailboxID) { data in
            data.serverRules.removeAll { $0.id == rule.id }
            data.serverRules.append(rule)
        }
        return rule
    }

    func deleteServerRule(id: String, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.serverRules.removeAll { $0.id == id }
        }
    }

    func reorderServerRules(ids: [String], mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            let rulesByID = Dictionary(data.serverRules.map { ($0.id, $0) }) { _, latest in latest }
            let ordered = ids.compactMap { rulesByID[$0] }
            let remaining = data.serverRules.filter { !ids.contains($0.id) }
            data.serverRules = ordered + remaining
        }
    }

    func syncHealth(mailboxID: Mailbox.ID) throws -> AccountSyncHealth {
        let data = try data(mailboxID: mailboxID)
        let conflictCount = data.replayConflicts.count
        if let existing = data.syncHealth {
            // Re-derive replayConflictCount from live conflict store so it
            // stays in sync even when the override was set before conflicts
            // were seeded.
            return AccountSyncHealth(
                sourceID: existing.sourceID,
                state: existing.state,
                lastSuccessfulSyncAt: existing.lastSuccessfulSyncAt,
                lastErrorDescription: existing.lastErrorDescription,
                indexStatus: existing.indexStatus,
                cacheSizeBytes: existing.cacheSizeBytes,
                localSearchIndexMetrics: existing.localSearchIndexMetrics,
                pendingMutationCount: existing.pendingMutationCount,
                replayConflictCount: conflictCount,
                backgroundRefreshSnapshot: existing.backgroundRefreshSnapshot
            )
        }
        let totalMessages = data.messagesByFolder.values.reduce(0) { $0 + $1.count }
        return AccountSyncHealth(
            sourceID: MailSourceID(accountID: mailboxes[0].id, mailboxID: mailboxID),
            state: .healthy,
            lastSuccessfulSyncAt: Date(),
            lastErrorDescription: nil,
            indexStatus: .ready(messageCount: totalMessages),
            cacheSizeBytes: totalMessages * 4096,
            localSearchIndexMetrics: localSearchIndexMetrics(for: data),
            pendingMutationCount: 0,
            replayConflictCount: conflictCount
        )
    }

    func setSyncHealth(_ state: SyncHealthState, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            let totalMessages = data.messagesByFolder.values.reduce(0) { $0 + $1.count }
            data.syncHealth = AccountSyncHealth(
                sourceID: MailSourceID(accountID: mailboxes[0].id, mailboxID: mailboxID),
                state: state,
                lastSuccessfulSyncAt: state == .healthy ? Date() : nil,
                lastErrorDescription: nil,
                indexStatus: .ready(messageCount: totalMessages),
                cacheSizeBytes: totalMessages * 4096,
                localSearchIndexMetrics: localSearchIndexMetrics(for: data),
                pendingMutationCount: 0
            )
        }
    }

    func setSyncHealthOverride(_ health: AccountSyncHealth, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.syncHealth = health
        }
    }

    func rebuildSearchIndex(mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            let totalMessages = data.messagesByFolder.values.reduce(0) { $0 + $1.count }
            data.syncHealth = AccountSyncHealth(
                sourceID: MailSourceID(accountID: mailboxes[0].id, mailboxID: mailboxID),
                state: .indexing,
                lastSuccessfulSyncAt: Date(),
                lastErrorDescription: nil,
                indexStatus: .ready(messageCount: totalMessages),
                cacheSizeBytes: totalMessages * 4096,
                localSearchIndexMetrics: localSearchIndexMetrics(for: data),
                pendingMutationCount: 0
            )
        }
    }

    func resetLocalCacheAndIndex(mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.syncHealth = AccountSyncHealth(
                sourceID: MailSourceID(accountID: mailboxes[0].id, mailboxID: mailboxID),
                state: .degraded,
                lastSuccessfulSyncAt: nil,
                lastErrorDescription: "Local cache reset; next sync will rebuild cached mail and indexes.",
                indexStatus: .notBuilt,
                cacheSizeBytes: 0,
                localSearchIndexMetrics: LocalSearchIndexMetrics(
                    databaseBytes: 0,
                    indexedHeaderCount: 0,
                    cachedBodyCount: 0,
                    searchDocumentCount: 0,
                    syncedFolderCount: 0
                ),
                pendingMutationCount: 0
            )
        }
    }

    private func localSearchIndexMetrics(for data: MockMailboxData) -> LocalSearchIndexMetrics {
        let totalMessages = data.messagesByFolder.values.reduce(0) { $0 + $1.count }
        return LocalSearchIndexMetrics(
            databaseBytes: Int64(totalMessages * 2048),
            indexedHeaderCount: totalMessages,
            cachedBodyCount: totalMessages,
            searchDocumentCount: totalMessages,
            syncedFolderCount: data.messagesByFolder.keys.count
        )
    }

    func replayConflicts(mailboxID: Mailbox.ID) throws -> [ReplayConflict] {
        // Newest first.
        try data(mailboxID: mailboxID).replayConflicts.reversed()
    }

    func dismissConflict(id: UUID, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.replayConflicts.removeAll { $0.id == id }
        }
    }

    func dismissAllConflicts(mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.replayConflicts.removeAll()
        }
    }

    /// Seeds a replay conflict into the mock store. Used by tests and
    /// preview configurations that want to verify the conflict review UI.
    func seedConflict(_ conflict: ReplayConflict, mailboxID: Mailbox.ID) throws {
        try updateData(mailboxID: mailboxID) { data in
            data.replayConflicts.append(conflict)
        }
    }

    func save(draft: Draft) throws -> Draft {
        try save(draft: draft, mailboxID: activeMailboxID)
    }

    func draft(for id: String, mailboxID: Mailbox.ID? = nil) throws -> Draft? {
        let drafts = try data(mailboxID: mailboxID ?? activeMailboxID).savedDrafts
        return drafts[id] ?? drafts.values.first { $0.remoteID == id }
    }

    func localDraftAttachments(for draft: Draft, mailboxID: Mailbox.ID? = nil) throws -> [MIMEMessageAttachment] {
        let data = try data(mailboxID: mailboxID ?? activeMailboxID)
        guard data.savedDrafts[draft.id] == draft else { throw MailBackendError.notFound(id: draft.id) }
        return try draft.attachmentIDs.map { id in
            guard let ownerID = data.attachmentDraftIDs[id],
                  ownerID == draft.id || ownerID == draft.remoteID,
                  let metadata = data.attachmentsByID[id], let bytes = data.attachmentDataByID[id] else {
                throw MailBackendError.notFound(id: id)
            }
            return MIMEMessageAttachment(id: id, filename: metadata.name, mimeType: metadata.mimeType, data: bytes)
        }
    }

    func save(draft: Draft, mailboxID: Mailbox.ID) throws -> Draft {
        try ensureActive()
        try reloadJournalRecords()
        if let delivered = journalRecords.last(where: {
            $0.sourceID.mailboxID == mailboxID && $0.draftID == draft.id && $0.state == .delivered
        }) {
            return delivered.draft ?? draft
        }
        if let queued = journalRecords.last(where: {
            $0.sourceID.mailboxID == mailboxID && $0.draftID == draft.id && $0.state == .queued
        }) {
            guard let frozen = queued.draft else { throw Self.storageError }
            return frozen
        }
        let sender = try sender(mailboxID: mailboxID)
        var saved = draft
        saved.remoteID = saved.remoteID ?? "draft-\(saved.id)"
        if let canceled = journalRecords.last(where: {
            $0.sourceID.mailboxID == mailboxID && $0.draftID == saved.id && $0.state == .canceled
        }) {
            let attachmentRecords = try Self.journalAttachments(for: saved, in: data(mailboxID: mailboxID))
            _ = try transactJournal { records in
                guard let index = records.firstIndex(where: { $0.recordID == canceled.recordID }) else {
                    throw ScheduledSendEditingError.notFound
                }
                if records[index].draft != saved { records[index].draftProjectionDate = now() }
                records[index].draft = saved
                records[index].attachments = attachmentRecords
                return ()
            }
        }
        let event = try updateData(mailboxID: mailboxID) { data -> MailEvent in
            let draftsFolderID = Self.ensureDraftsFolderID(in: &data)
            let draftID = draft.remoteID ?? "draft-\(draft.id)"
            let existed = data.messagesByFolder[draftsFolderID, default: []].contains {
                $0.id == draftID
            }
            saved.remoteID = draftID
            data.savedDrafts[saved.id] = saved

            data.messagesByFolder[draftsFolderID, default: []].removeAll { $0.id == draftID }
            data.messagesByFolder[draftsFolderID, default: []].append(
                MessageHeader(
                    id: draftID,
                    threadID: Self.threadID(for: draft, in: data) ?? draftID,
                    folderID: draftsFolderID,
                    from: sender,
                    to: draft.to,
                    cc: draft.cc,
                    bcc: draft.bcc,
                    subject: draft.subject,
                    snippet: Self.snippet(from: draft.htmlBody),
                    date: Date(),
                    isRead: true,
                    hasAttachments: !draft.attachmentIDs.isEmpty
                )
            )
            data.messageBodies[draftID] = MessageBody(
                messageID: draftID,
                html: draft.htmlBody,
                plainText: HTMLTextStripper.plainText(from: draft.htmlBody),
                attachments: Self.attachments(for: draft.attachmentIDs, in: data)
            )

            return existed
                ? .messagesUpdated(folderID: draftsFolderID, messageIDs: [draftID])
                : .messagesAdded(folderID: draftsFolderID, messageIDs: [draftID])
        }
        emit(event)
        return saved
    }

    func discard(draftID: String) throws {
        try discard(draftID: draftID, mailboxID: activeMailboxID)
    }

    func discard(draftID: String, mailboxID: Mailbox.ID) throws {
        try ensureActive()
        try reloadJournalRecords()
        let existingDraft = try draft(for: draftID, mailboxID: mailboxID)
            ?? draft(for: "draft-\(draftID)", mailboxID: mailboxID)
        if let existingDraft, journalRecords.contains(where: {
            $0.sourceID.mailboxID == mailboxID && $0.draftID == existingDraft.id && $0.state == .delivered
        }) { return }
        var changedSchedule = false
        if let existingDraft,
           let canceled = journalRecords.last(where: {
               $0.sourceID.mailboxID == mailboxID && $0.draftID == existingDraft.id
                   && ($0.state == .queued || $0.state == .canceled)
           }) {
            _ = try transactJournal { records in
                guard let index = records.firstIndex(where: { $0.recordID == canceled.recordID }) else {
                    throw ScheduledSendEditingError.notFound
                }
                records[index].state = .canceled
                records[index].draft = nil
                records[index].draftProjectionDate = nil
                records[index].attachments = []
                records[index].scheduledFor = nil
                return ()
            }
            changedSchedule = true
        }
        let event = try updateData(mailboxID: mailboxID) { data in
            Self.removeDraft(draftID: draftID, in: &data)
        }
        if let existingDraft { dataByMailboxID[mailboxID]?.savedDrafts[existingDraft.id] = nil }
        refreshScheduledSnapshot()
        if let event {
            emit(event)
        }
        if changedSchedule { emit(.outboxChanged) }
    }

    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) throws -> String {
        try uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType,
            mailboxID: activeMailboxID
        )
    }

    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        mailboxID: Mailbox.ID
    ) throws -> String {
        try ensureActive()
        return try updateData(mailboxID: mailboxID) { mailboxData in
            let attachmentID = "attachment-\(draftID)-\(mailboxData.attachmentsByID.count + 1)"
            mailboxData.attachmentsByID[attachmentID] = Attachment(
                id: attachmentID,
                name: filename,
                mimeType: mimeType,
                sizeBytes: data.count,
                resource: attachmentID
            )
            mailboxData.attachmentDataByID[attachmentID] = data
            mailboxData.attachmentDraftIDs[attachmentID] = draftID
            return attachmentID
        }
    }

    func send(draft: Draft) throws -> String {
        try send(draft: draft, mailboxID: activeMailboxID)
    }

    func send(
        draft: Draft,
        mailboxID: Mailbox.ID,
        scheduledDelivery: (
            recordID: String,
            scheduleID: String,
            at: Date,
            sender: Correspondent,
            parentMessageID: String?,
            references: [String]
        )? = nil
    ) throws -> String {
        try ensureActive()
        try reloadJournalRecords()
        if let delivered = journalRecords.last(where: {
            $0.sourceID.mailboxID == mailboxID && $0.draftID == draft.id && $0.state == .delivered
        })?.sentHeader {
            return delivered.id
        }
        var canonical = draft
        canonical.remoteID = canonical.remoteID ?? "draft-\(draft.id)"
        canonical.scheduledFor = nil
        let sourceID = MailSourceID(accountID: accountID, mailboxID: mailboxID)
        let originalData = try data(mailboxID: mailboxID)
        let attachments = try Self.journalAttachments(for: canonical, in: originalData)
        let currentSender = try sender(mailboxID: mailboxID)
        let from = scheduledDelivery?.sender ?? currentSender
        let parent = canonical.inReplyToMessageID.flatMap { parentID in
            originalData.messagesByFolder.values.flatMap(\.self).first { $0.id == parentID }
        }
        let parentMessageID: String?
        let references: [String]
        if let scheduledDelivery {
            parentMessageID = scheduledDelivery.parentMessageID
            references = scheduledDelivery.references
        } else {
            parentMessageID = parent?.rfcMessageID
            references = Self.deduplicatedReferences((parent?.references ?? []) + [parentMessageID].compactMap { $0 })
        }
        var updatedData = originalData
        let draftsFolderID = Self.ensureDraftsFolderID(in: &updatedData)
        let draftRemoteID = canonical.remoteID ?? "draft-\(canonical.id)"
        _ = Self.removeDraft(draftID: draftRemoteID, in: &updatedData)
        updatedData.savedDrafts[canonical.id] = nil
        let sentFolderID = Self.ensureSentFolderID(in: &updatedData)
        let messageID = "sent-\(draft.remoteID ?? draft.id)"
        let existingHeader = originalData.messagesByFolder.values.flatMap(\.self).first { $0.id == messageID }
        let header = existingHeader ?? MessageHeader(
            id: messageID,
            threadID: Self.threadID(for: canonical, in: originalData) ?? canonical.threadID ?? messageID,
            folderID: sentFolderID,
            from: from,
            to: canonical.to,
            cc: canonical.cc,
            bcc: canonical.bcc,
            subject: canonical.subject,
            snippet: Self.snippet(from: canonical.htmlBody),
            date: now(),
            isRead: true,
            isAnswered: false,
            isForwarded: false,
            hasAttachments: !canonical.attachmentIDs.isEmpty,
            messageID: MIMEMessageBuilder.messageIDHeaderValue(draftID: canonical.id, fromEmail: from.email),
            inReplyTo: parentMessageID,
            references: references.isEmpty ? nil : references
        )
        let body = originalData.messageBodies[messageID] ?? MessageBody(
            messageID: messageID,
            html: canonical.htmlBody,
            plainText: HTMLTextStripper.plainText(from: canonical.htmlBody),
            attachments: Self.attachments(for: canonical.attachmentIDs, in: originalData)
        )
        updatedData.messagesByFolder[sentFolderID, default: []].removeAll { $0.id == messageID }
        updatedData.messagesByFolder[sentFolderID, default: []].append(header)
        updatedData.messageBodies[messageID] = body
        if let replyID = canonical.inReplyToMessageID {
            Self.updateHeader(id: replyID, in: &updatedData) { $0.isAnswered = true }
        }
        if let forwardedID = canonical.forwardedMessageID {
            Self.updateHeader(id: forwardedID, in: &updatedData) { $0.isForwarded = true }
        }
        let committed: (messageID: String, changed: Bool)
        do {
            committed = try transactJournal { records in
                if let delivered = records.last(where: {
                    $0.sourceID == sourceID && $0.draftID == canonical.id && $0.state == .delivered
                }), let sentHeader = delivered.sentHeader {
                    return (sentHeader.id, false)
                }
                try Self.validateScheduledDelivery(
                    scheduledDelivery,
                    sourceID: sourceID,
                    draft: draft,
                    records: records
                )
                if let index = records.lastIndex(where: {
                    $0.sourceID == sourceID && $0.draftID == canonical.id && $0.state != .delivered
                }) {
                    records[index].state = .delivered
                    records[index].draft = canonical
                    records[index].attachments = attachments
                    records[index].scheduledFor = nil
                    records[index].sentHeader = header
                    records[index].sentBody = body
                    records[index].nextAttemptAt = nil
                    records[index].sender = from
                    records[index].parentMessageID = parentMessageID
                    records[index].references = references
                    records[index].draftProjectionDate = nil
                } else {
                    records.append(MockSendJournalRecord(
                        recordID: UUID().uuidString,
                        accountID: accountID,
                        sourceID: sourceID,
                        draftID: canonical.id,
                        scheduleID: nil,
                        draft: canonical,
                        attachments: attachments,
                        state: .delivered,
                        scheduledFor: nil,
                        sentHeader: header,
                        sentBody: body,
                        nextAttemptAt: nil,
                        sender: from,
                        parentMessageID: parentMessageID,
                        references: references
                    ))
                }
                return (messageID, true)
            }
        } catch { throw Self.storageError }
        guard committed.changed else { return committed.messageID }
        if journal == nil { dataByMailboxID[mailboxID] = updatedData }
        emit(.messagesAdded(folderID: sentFolderID, messageIDs: [committed.messageID]))
        emit(.messagesRemoved(folderID: draftsFolderID, messageIDs: [draftRemoteID]))
        emit(.outboxChanged)
        return committed.messageID
    }

    private static func validateScheduledDelivery(
        _ scheduledDelivery: (
            recordID: String,
            scheduleID: String,
            at: Date,
            sender: Correspondent,
            parentMessageID: String?,
            references: [String]
        )?,
        sourceID: MailSourceID,
        draft: Draft,
        records: [MockSendJournalRecord]
    ) throws {
        guard let scheduledDelivery else { return }
        guard let record = records.first(where: { $0.recordID == scheduledDelivery.recordID }),
              record.state == .queued,
              record.scheduleID == scheduledDelivery.scheduleID,
              record.sourceID == sourceID,
              record.draft == draft,
              let dueDate = record.scheduledFor,
              dueDate <= scheduledDelivery.at,
              (record.nextAttemptAt ?? .distantPast) <= scheduledDelivery.at else {
            throw ScheduledSendEditingError.notFound
        }
    }

    private static func deduplicatedReferences(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func ensureSentFolderID(in data: inout MockMailboxData) -> String {
        if let sent = data.folders.first(where: { $0.role == .sent }) {
            return sent.id
        }
        let fallbackID = "sent"
        data.folders.append(Folder(id: fallbackID, name: "Sent", role: .sent))
        return fallbackID
    }

    private static func ensureDraftsFolderID(in data: inout MockMailboxData) -> String {
        if let drafts = data.folders.first(where: { $0.role == .drafts }) {
            return drafts.id
        }
        let fallbackID = "drafts"
        data.folders.append(Folder(id: fallbackID, name: "Drafts", role: .drafts))
        return fallbackID
    }

    private static func ensureTrashFolderID(in data: inout MockMailboxData) -> String {
        if let trash = data.folders.first(where: { $0.role == .trash }) {
            return trash.id
        }
        let fallbackID = "trash"
        data.folders.append(Folder(id: fallbackID, name: "Trash", role: .trash))
        return fallbackID
    }

    private static func updateHeader(
        id: String,
        in data: inout MockMailboxData,
        update: (inout MessageHeader) -> Void
    ) {
        for folderID in Array(data.messagesByFolder.keys) {
            guard var headers = data.messagesByFolder[folderID],
                  let index = headers.firstIndex(where: { $0.id == id }) else { continue }
            update(&headers[index])
            data.messagesByFolder[folderID] = headers
            return
        }
    }

    @discardableResult
    private static func removeDraft(draftID: String, in data: inout MockMailboxData) -> MailEvent? {
        guard let draftsFolderID = data.folders.first(where: { $0.role == .drafts })?.id else {
            return nil
        }
        let existing = data.messagesByFolder[draftsFolderID] ?? []
        // Drafts are staged under the folder message id `draft-<Draft.id>`
        // (or the draft's remoteID once saved), but callers discard by the
        // draft's local id — match both forms so `discard(draftID:)` keeps
        // the same local-id contract the other backends expose.
        let candidateIDs = Set([draftID, "draft-\(draftID)"])
        let removed = existing.filter { candidateIDs.contains($0.id) }.map(\.id)
        guard !removed.isEmpty else { return nil }
        data.messagesByFolder[draftsFolderID] = existing.filter { !candidateIDs.contains($0.id) }
        for id in removed {
            data.messageBodies[id] = nil
        }
        data.savedDrafts = data.savedDrafts.filter { !removed.contains($0.value.remoteID ?? "") }
        return .messagesRemoved(folderID: draftsFolderID, messageIDs: removed)
    }

    private static func attachments(for ids: [String], in data: MockMailboxData) -> [Attachment] {
        ids.compactMap { data.attachmentsByID[$0] }
    }

    private static func threadID(for draft: Draft, in data: MockMailboxData) -> String? {
        guard let replyID = draft.inReplyToMessageID else { return nil }
        return data.messagesByFolder.values.flatMap(\.self).first { $0.id == replyID }?.threadID
    }

    private static func copy(_ header: MessageHeader, folderID: Folder.ID) -> MessageHeader {
        MessageHeader(
            id: header.id,
            threadID: header.threadID,
            folderID: folderID,
            from: header.from,
            to: header.to,
            cc: header.cc,
            bcc: header.bcc,
            subject: header.subject,
            snippet: header.snippet,
            date: header.date,
            isRead: header.isRead,
            isFlagged: header.isFlagged,
            isAnswered: header.isAnswered,
            isForwarded: header.isForwarded,
            hasAttachments: header.hasAttachments,
            flagColor: header.flagColor,
            messageID: header.messageID,
            inReplyTo: header.inReplyTo,
            references: header.references,
            labels: header.labels
        )
    }

    private static func snippet(from body: String) -> String {
        // Drafts carry their markup in `htmlBody`; sent/draft copies mirror a
        // real message's multipart/alternative split, so snippets need the
        // markup stripped to stay readable in the message list.
        let trimmed = ((try? HTMLTextStripper.visibleText(from: Data(body.utf8))) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 160 else { return trimmed }
        return String(trimmed.prefix(157)) + "..."
    }

    private func folder(id: Folder.ID, mailboxID: Mailbox.ID) throws -> Folder {
        guard let folder = try data(mailboxID: mailboxID).folders.first(where: { $0.id == id }) else {
            throw MailBackendError.notFound(id: id)
        }
        return folder
    }

    private func folderSubtreeIDs(rootID: Folder.ID, mailboxID: Mailbox.ID) throws -> Set<Folder.ID> {
        let folders = try data(mailboxID: mailboxID).folders
        var remainingParents: [Folder.ID] = [rootID]
        var collected: Set<Folder.ID> = [rootID]

        while let parentID = remainingParents.popLast() {
            let children = folders.filter { $0.parentID == parentID }.map(\.id)
            for childID in children where !collected.contains(childID) {
                collected.insert(childID)
                remainingParents.append(childID)
            }
        }

        return collected
    }

    private static func slug(from name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { character -> Character in
            switch character {
            case "a" ... "z", "0" ... "9":
                character
            default:
                "-"
            }
        }
        let raw = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let squashed = raw.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return squashed.isEmpty ? "folder" : squashed
    }

    private static func uniqueFolderID(base: String, existingIDs: Set<Folder.ID>) -> Folder.ID {
        guard existingIDs.contains(base) else { return base }
        var suffix = 2
        var candidate = "\(base)-\(suffix)"
        while existingIDs.contains(candidate) {
            suffix += 1
            candidate = "\(base)-\(suffix)"
        }
        return candidate
    }

    nonisolated func eventStream() -> AsyncStream<MailEvent> {
        AsyncStream { continuation in
            let token = UUID()
            Task { await self.register(token: token, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(token: token) }
            }
        }
    }

    func register(token: UUID, continuation: AsyncStream<MailEvent>.Continuation) {
        continuations[token] = continuation
    }

    func unregister(token: UUID) {
        continuations.removeValue(forKey: token)
    }

    func emit(_ event: MailEvent) {
        for c in continuations.values {
            c.yield(event)
        }
    }
}

extension MockBackend: CachedMessageBodyProviding {
    public func cachedBody(for messageID: MessageHeader.ID, sourceID: MailSourceID?) async -> MessageBody? {
        if let sourceID {
            return try? await body(for: messageID, sourceID: sourceID)
        }
        return try? await body(for: messageID)
    }
}
