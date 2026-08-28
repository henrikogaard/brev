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

/// An in-memory `MailBackend` used by SwiftUI previews, snapshot
/// tests, and design-system development. Never instantiated in the
/// shipping app.
///
/// State is held in an internal actor so concurrent calls from multiple
/// tasks behave sanely. Canned data is seeded at construction; mutating
/// operations update the in-memory state and emit `MailEvent`s on the
/// stream returned by `subscribeToChanges()`.
public final class MockBackend: MailBackend, AutoReplyManaging, ServerRuleManaging, ContactLookupProviding, MailImporting,
    SyncHealthReporting, SyncHealthRepairing, SyncConflictManaging, @unchecked Sendable {
    public let account: BrevAccount
    public let capabilities: BackendCapabilities

    private let store: Store
    private let contacts: [ContactLookupResult]

    public init(
        account: BrevAccount = .preview,
        capabilities: BackendCapabilities = .full,
        folders: [Folder] = MockBackend.previewFolders,
        messagesByFolder: [String: [MessageHeader]] = MockBackend.previewMessages,
        mailboxes: [Mailbox]? = nil,
        contacts: [ContactLookupResult]? = nil
    ) {
        self.account = account
        self.capabilities = capabilities
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
        store = Store(
            mailboxes: resolvedMailboxes,
            dataByMailboxID: Self.previewMailboxData(
                mailboxes: resolvedMailboxes,
                primaryFolders: folders,
                primaryMessagesByFolder: messagesByFolder
            )
        )
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

    public func connect() async throws { /* no-op */ }
    public func disconnect() async { /* no-op */ }

    public func folders() async throws -> [Folder] {
        await store.folderSnapshots()
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
        let all = await store.messages(in: folder.id)
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

    public func discard(draftID: String) async throws {
        await store.discard(draftID: draftID)
    }

    public func discard(draftID: String, sourceID: MailSourceID) async throws {
        try await store.discard(draftID: draftID, mailboxID: mailboxID(for: sourceID))
    }

    public func uploadAttachment(draftID: String, data: Data, filename: String, mimeType: String) async throws -> String {
        await store.uploadAttachment(
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
        let messageID = try await store.send(draft: draft)
        return SendResult(sentMessageID: messageID, scheduledFor: draft.scheduledFor)
    }

    public func send(draft: Draft, sourceID: MailSourceID) async throws -> SendResult {
        let messageID = try await store.send(draft: draft, mailboxID: mailboxID(for: sourceID))
        return SendResult(sentMessageID: messageID, scheduledFor: draft.scheduledFor)
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
        default:
            return nil
        }
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
        backendIdentifier: "demo",
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

    init(
        mailboxes: [Mailbox],
        dataByMailboxID: [Mailbox.ID: MockMailboxData]
    ) {
        self.mailboxes = mailboxes
        activeMailboxID = mailboxes.first(where: \.isPrimary)?.id ?? mailboxes[0].id
        self.dataByMailboxID = dataByMailboxID
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

    func messages(in folderID: String) -> [MessageHeader] {
        (try? messages(in: folderID, mailboxID: activeMailboxID)) ?? []
    }

    func messages(in folderID: String, mailboxID: Mailbox.ID) throws -> [MessageHeader] {
        try (data(mailboxID: mailboxID).messagesByFolder[folderID] ?? [])
            .sorted { $0.date > $1.date }
    }

    func folderSnapshots() -> [Folder] {
        (try? folderSnapshots(mailboxID: activeMailboxID)) ?? []
    }

    func folderSnapshots(mailboxID: Mailbox.ID) throws -> [Folder] {
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
            html: "<p>Preview body for <code>\(messageID)</code>.</p>",
            plainText: "Preview body for \(messageID).",
            attachments: [],
            listUnsubscribe: messageID == "m7"
                ? ListUnsubscribeOptions.parse(
                    listUnsubscribe: "<https://news.example.org/unsubscribe>, <mailto:unsubscribe@news.example.org>",
                    listUnsubscribePost: nil
                )
                : nil
        )
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

    func save(draft: Draft, mailboxID: Mailbox.ID) throws -> Draft {
        let sender = try sender(mailboxID: mailboxID)
        var saved = draft
        let event = try updateData(mailboxID: mailboxID) { data -> MailEvent in
            let draftsFolderID = Self.ensureDraftsFolderID(in: &data)
            let draftID = draft.remoteID ?? "draft-\(draft.id)"
            let existed = data.messagesByFolder[draftsFolderID, default: []].contains {
                $0.id == draftID
            }
            saved.remoteID = draftID

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
                plainText: draft.htmlBody,
                attachments: Self.attachments(for: draft.attachmentIDs, in: data)
            )

            return existed
                ? .messagesUpdated(folderID: draftsFolderID, messageIDs: [draftID])
                : .messagesAdded(folderID: draftsFolderID, messageIDs: [draftID])
        }
        emit(event)
        return saved
    }

    func discard(draftID: String) {
        try? discard(draftID: draftID, mailboxID: activeMailboxID)
    }

    func discard(draftID: String, mailboxID: Mailbox.ID) throws {
        let event = try updateData(mailboxID: mailboxID) { data in
            Self.removeDraft(draftID: draftID, in: &data)
        }
        if let event {
            emit(event)
        }
    }

    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) -> String {
        (try? uploadAttachment(
            draftID: draftID,
            data: data,
            filename: filename,
            mimeType: mimeType,
            mailboxID: activeMailboxID
        )) ?? "attachment-\(draftID)"
    }

    func uploadAttachment(
        draftID: String,
        data: Data,
        filename: String,
        mimeType: String,
        mailboxID: Mailbox.ID
    ) throws -> String {
        try updateData(mailboxID: mailboxID) { mailboxData in
            let attachmentID = "attachment-\(draftID)-\(mailboxData.attachmentsByID.count + 1)"
            mailboxData.attachmentsByID[attachmentID] = Attachment(
                id: attachmentID,
                name: filename,
                mimeType: mimeType,
                sizeBytes: data.count,
                resource: attachmentID
            )
            mailboxData.attachmentDataByID[attachmentID] = data
            return attachmentID
        }
    }

    func send(draft: Draft) throws -> String {
        try send(draft: draft, mailboxID: activeMailboxID)
    }

    func send(draft: Draft, mailboxID: Mailbox.ID) throws -> String {
        let sender = try sender(mailboxID: mailboxID)
        if let draftID = draft.remoteID {
            try discard(draftID: draftID, mailboxID: mailboxID)
        }
        if let replyID = draft.inReplyToMessageID {
            try mutate(ids: [replyID], mailboxID: mailboxID) { $0.isAnswered = true }
        }
        if let forwardedID = draft.forwardedMessageID {
            try mutate(ids: [forwardedID], mailboxID: mailboxID) { $0.isForwarded = true }
        }
        let result = try updateData(mailboxID: mailboxID) { data -> (messageID: String, event: MailEvent) in
            let sentFolderID = Self.ensureSentFolderID(in: &data)
            let messageID = "sent-\(draft.remoteID ?? draft.id)"
            let header = MessageHeader(
                id: messageID,
                threadID: Self.threadID(for: draft, in: data) ?? messageID,
                folderID: sentFolderID,
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

            data.messagesByFolder[sentFolderID, default: []].removeAll { $0.id == messageID }
            data.messagesByFolder[sentFolderID, default: []].append(header)
            data.messageBodies[messageID] = MessageBody(
                messageID: messageID,
                plainText: draft.htmlBody,
                attachments: Self.attachments(for: draft.attachmentIDs, in: data)
            )
            return (
                messageID,
                .messagesAdded(folderID: sentFolderID, messageIDs: [messageID])
            )
        }
        emit(result.event)
        return result.messageID
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

    @discardableResult
    private static func removeDraft(draftID: String, in data: inout MockMailboxData) -> MailEvent? {
        guard let draftsFolderID = data.folders.first(where: { $0.role == .drafts })?.id else {
            return nil
        }
        let existing = data.messagesByFolder[draftsFolderID] ?? []
        let removed = existing.filter { $0.id == draftID }.map(\.id)
        guard !removed.isEmpty else { return nil }
        data.messagesByFolder[draftsFolderID] = existing.filter { $0.id != draftID }
        data.messageBodies[draftID] = nil
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
            labels: header.labels
        )
    }

    private static func snippet(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
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
