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

@testable import BrevBackend
import Foundation
import Testing

@Suite("MockBackend") struct MockBackendTests {
    @Test("seeded folders are returned in order")
    func seededFoldersAreReturnedInOrder() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        #expect(folders.first?.role == .inbox)
        #expect(folders.contains(where: { $0.role == .sent }))
    }

    @Test("inbox messages are sorted newest-first")
    func inboxMessagesAreSortedNewestFirst() async throws {
        let backend = MockBackend()
        let inbox = try await backend.folders().first(where: { $0.role == .inbox })!
        let (headers, next) = try await backend.messages(in: inbox, pageToken: nil)
        #expect(next == nil)
        #expect(!headers.isEmpty)
        let dates = headers.map(\.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("folder counts are derived from current messages")
    func folderCountsAreDerivedFromCurrentMessages() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)

        #expect(inbox.totalCount == headers.count)
        #expect(inbox.unreadCount == headers.filter { !$0.isRead }.count)
    }

    @Test("preview inbox includes enough example mail for grouped demos")
    func previewInboxIncludesEnoughExampleMailForGroupedDemos() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)

        #expect(headers.count >= 12)
        #expect(Set(headers.map(\.from.email)).count >= 8)
        #expect(headers.contains { $0.date < Date().addingTimeInterval(-14 * 86400) })
        #expect(headers.contains { $0.date < Date().addingTimeInterval(-30 * 86400) })
    }

    @Test("preview folders include nested custom mailbox groups")
    func previewFoldersIncludeNestedCustomMailboxGroups() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()

        let archive = try #require(folders.first { $0.id == "archive" })
        let receipts = try #require(folders.first { $0.id == "archive-receipts" })
        let licenses = try #require(folders.first { $0.id == "archive-receipts-licenses" })
        let mailspring = try #require(folders.first { $0.id == "mailspring" })
        let mailspringSnoozed = try #require(folders.first { $0.id == "mailspring-snoozed" })

        #expect(receipts.parentID == archive.id)
        #expect(licenses.parentID == receipts.id)
        #expect(mailspringSnoozed.parentID == mailspring.id)
    }

    @Test("createFolder adds a custom child and emits folderRefreshed")
    func createFolderAddsCustomChildAndEmitsFolderRefreshed() async throws {
        let backend = MockBackend()
        let archive = try #require(await backend.folders().first(where: { $0.id == "archive" }))
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        let created = try await backend.createFolder(name: "Travel", parentID: archive.id)

        #expect(created.role == .custom)
        #expect(created.parentID == archive.id)
        let folders = try await backend.folders()
        #expect(folders.contains { $0.id == created.id && $0.name == "Travel" })
        let event = try await nextEvent(from: stream)
        #expect(event == .folderRefreshed(folderID: created.id))
    }

    @Test("mail import service persists imported messages into a folder")
    func mailImportServicePersistsImportedMessagesIntoFolder() async throws {
        let backend = MockBackend()
        let importer = try #require(backend.extensionService(MailImporting.self))
        let folder = try await backend.createFolder(name: "Imported Archive", parentID: nil)
        let message = ImportedMessage(
            headers: [
                (name: "Message-ID", value: "<archive-1@example.org>"),
                (name: "From", value: "Ada Lovelace <ada@example.org>"),
                (name: "To", value: "Henrik <henrik@example.org>"),
                (name: "Subject", value: "Imported hello"),
                (name: "Date", value: "Thu, 1 Jan 2026 10:30:00 +0000")
            ],
            bodyData: Data("Imported body text.".utf8)
        )

        let summary = try await importer.importMessages([message], into: folder)

        #expect(summary.importedCount == 1)
        #expect(summary.errors.isEmpty)
        let refreshedFolder = try #require(await backend.folders().first(where: { $0.id == folder.id }))
        #expect(refreshedFolder.totalCount == 1)
        let (headers, _) = try await backend.messages(in: refreshedFolder, pageToken: nil)
        let imported = try #require(headers.first)
        #expect(imported.id == "archive-1@example.org")
        #expect(imported.subject == "Imported hello")
        #expect(imported.from.email == "ada@example.org")
        let body = try await backend.body(for: imported.id)
        #expect(body.plainText == "Imported body text.")
    }

    @Test("renameFolder updates a custom folder name")
    func renameFolderUpdatesCustomFolderName() async throws {
        let backend = MockBackend()
        let renamed = try await backend.renameFolder(id: "archive-travel", name: "Trips")
        #expect(renamed.id == "archive-travel")
        #expect(renamed.name == "Trips")
        let folders = try await backend.folders()
        #expect(folders.first(where: { $0.id == "archive-travel" })?.name == "Trips")
    }

    @Test("deleteFolder removes folder subtree")
    func deleteFolderRemovesFolderSubtree() async throws {
        let backend = MockBackend()

        try await backend.deleteFolder(id: "archive-receipts")

        let folders = try await backend.folders()
        #expect(!folders.contains { $0.id == "archive-receipts" })
        #expect(!folders.contains { $0.id == "archive-receipts-licenses" })
    }

    @Test("flushFolder removes messages from the folder")
    func flushFolderRemovesMessagesFromFolder() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let beforePage = try await backend.messages(in: inbox, pageToken: nil)
        let before = beforePage.headers.count
        #expect(before > 0)

        try await backend.flushFolder(id: inbox.id)

        let afterPage = try await backend.messages(in: inbox, pageToken: nil)
        let after = afterPage.headers.count
        #expect(after == 0)
    }

    @Test("folder mutations require capabilities")
    func folderMutationsRequireCapabilities() async throws {
        let backend = MockBackend(capabilities: [])

        await #expect(throws: MailBackendError.self) {
            try await backend.createFolder(name: "Blocked", parentID: nil)
        }
        await #expect(throws: MailBackendError.self) {
            try await backend.renameFolder(id: "archive-travel", name: "Blocked")
        }
        await #expect(throws: MailBackendError.self) {
            try await backend.deleteFolder(id: "archive-travel")
        }
        await #expect(throws: MailBackendError.self) {
            try await backend.flushFolder(id: "trash")
        }
    }

    @Test("setRead toggles flag and emits messagesUpdated")
    func setReadTogglesAndEmits() async throws {
        let backend = MockBackend()
        let inbox = try await backend.folders().first(where: { $0.role == .inbox })!
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let target = headers.first(where: { !$0.isRead })!

        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)
        try await backend.setRead(true, for: [target.id])

        let event = try await nextEvent(from: stream)
        if case .messagesUpdated(folderID: let folderID, messageIDs: let ids) = event {
            #expect(folderID == inbox.id)
            #expect(ids.contains(target.id))
        } else {
            Issue.record("expected messagesUpdated event, got \(String(describing: event))")
        }
    }

    @Test("setRead updates folder unread count")
    func setReadUpdatesFolderUnreadCount() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let unread = try #require(headers.first(where: { !$0.isRead }))

        try await backend.setRead(true, for: [unread.id])

        let updatedInbox = try #require(await backend.folders().first(where: { $0.id == inbox.id }))
        #expect(updatedInbox.unreadCount == inbox.unreadCount - 1)
    }

    @Test("copy leaves source message and adds destination message")
    func copyLeavesSourceMessageAndAddsDestinationMessage() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let archive = try #require(await backend.folders().first(where: { $0.role == .archive }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let target = try #require(headers.first)
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.copy(messageIDs: [target.id], to: archive)

        let (sourceHeaders, _) = try await backend.messages(in: inbox, pageToken: nil)
        let (destinationHeaders, _) = try await backend.messages(in: archive, pageToken: nil)
        #expect(sourceHeaders.contains { $0.id == target.id })
        #expect(destinationHeaders.contains { $0.id == target.id && $0.folderID == archive.id })
        let event = try await nextEvent(from: stream)
        if case .messagesAdded(folderID: let folderID, messageIDs: let ids) = event {
            #expect(folderID == archive.id)
            #expect(ids == [target.id])
        } else {
            Issue.record("expected messagesAdded event, got \(String(describing: event))")
        }
    }

    @Test("delete emits removed message ids")
    func deleteEmitsRemovedMessageIDs() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let target = try #require(headers.first)
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.delete(messageIDs: [target.id])

        let event = try await nextEvent(from: stream)
        if case .messagesRemoved(folderID: let folderID, messageIDs: let ids) = event {
            #expect(folderID == inbox.id)
            #expect(ids == [target.id])
        } else {
            Issue.record("expected messagesRemoved event, got \(String(describing: event))")
        }
    }

    @Test("delete updates folder total and unread counts")
    func deleteUpdatesFolderCounts() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let unread = try #require(headers.first(where: { !$0.isRead }))

        try await backend.delete(messageIDs: [unread.id])

        let updatedInbox = try #require(await backend.folders().first(where: { $0.id == inbox.id }))
        #expect(updatedInbox.totalCount == inbox.totalCount - 1)
        #expect(updatedInbox.unreadCount == inbox.unreadCount - 1)
    }

    @Test("delete moves non-trash messages to Trash and emits an add event")
    func deleteMovesNonTrashMessagesToTrashAndEmitsAdd() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let trash = try #require(await backend.folders().first(where: { $0.role == .trash }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let target = try #require(headers.first)
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.delete(messageIDs: [target.id])

        let added = try await nextEvent(from: stream) {
            if case .messagesAdded(folderID: trash.id, messageIDs: [target.id]) = $0 {
                return true
            }
            return false
        }
        #expect(added != nil)

        let (updatedInboxHeaders, _) = try await backend.messages(in: inbox, pageToken: nil)
        #expect(!updatedInboxHeaders.contains { $0.id == target.id })
        let (trashHeaders, _) = try await backend.messages(in: trash, pageToken: nil)
        let trashed = try #require(trashHeaders.first { $0.id == target.id })
        #expect(trashed.folderID == trash.id)

        let updatedTrash = try #require(await backend.folders().first(where: { $0.id == trash.id }))
        #expect(updatedTrash.totalCount == trash.totalCount + 1)
    }

    @Test("delete permanently removes messages already in Trash")
    func deletePermanentlyRemovesMessagesAlreadyInTrash() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let trash = try #require(await backend.folders().first(where: { $0.role == .trash }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let target = try #require(headers.first)
        try await backend.delete(messageIDs: [target.id])
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.delete(messageIDs: [target.id])

        let removed = try await nextEvent(from: stream) {
            if case .messagesRemoved(folderID: trash.id, messageIDs: [target.id]) = $0 {
                return true
            }
            return false
        }
        #expect(removed != nil)
        let (trashHeaders, _) = try await backend.messages(in: trash, pageToken: nil)
        #expect(!trashHeaders.contains { $0.id == target.id })
    }

    @Test("search matches subject substring case-insensitively")
    func searchMatchesSubjectSubstring() async throws {
        let backend = MockBackend()
        let hits = try await backend.search(SearchQuery(text: "weekend"))
        #expect(hits.contains(where: { $0.subject.lowercased().contains("weekend") }))
    }

    @Test("search respects folder filter")
    func searchRespectsFolderFilter() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))

        let hits = try await backend.search(SearchQuery(text: "weekend", folderID: inbox.id))

        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.folderID == inbox.id })
        #expect(!hits.contains { $0.id == "s1" })
    }

    @Test("search respects attachment filter")
    func searchRespectsAttachmentFilter() async throws {
        let backend = MockBackend()

        let hits = try await backend.search(SearchQuery(text: "Hemsedal", hasAttachments: true))

        #expect(hits.map(\.id) == ["m1"])
    }

    @Test("seeded attachment messages expose downloadable invite bodies")
    func seededAttachmentMessagesExposeDownloadableInviteBodies() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let header = try #require(headers.first(where: { $0.hasAttachments }))

        let body = try await backend.body(for: header.id)
        let attachment = try #require(body.attachments.first)
        #expect(attachment.name.hasSuffix(".ics"))
        #expect(attachment.mimeType.hasPrefix("text/calendar"))
        #expect(attachment.resource != nil)

        let downloaded = try await backend.downloadAttachment(attachment)
        let text = String(decoding: downloaded, as: UTF8.self)
        #expect(text.contains("BEGIN:VCALENDAR"))
        #expect(text.contains("SUMMARY:Hytte weekend in Hemsedal"))
    }

    @Test("calendar invite replies mark the message answered and emit an update")
    func calendarInviteRepliesMarkMessageAnsweredAndEmitUpdate() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let header = try #require(headers.first(where: { $0.hasAttachments }))
        #expect(!header.isAnswered)
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        try await backend.replyToCalendarInvite(messageID: header.id, response: .accepted)

        let event = try await nextEvent(from: stream)
        if case .messagesUpdated(folderID: let folderID, messageIDs: let ids) = event {
            #expect(folderID == inbox.id)
            #expect(ids == [header.id])
        } else {
            Issue.record("expected messagesUpdated event, got \(String(describing: event))")
        }
        let (updatedHeaders, _) = try await backend.messages(in: inbox, pageToken: nil)
        let updatedHeader = try #require(updatedHeaders.first { $0.id == header.id })
        #expect(updatedHeader.isAnswered)
    }

    @Test("calendar invite replies require the server-side reply capability")
    func calendarInviteRepliesRequireCapability() async throws {
        let backend = MockBackend(capabilities: [])

        await #expect(throws: MailBackendError.self) {
            try await backend.replyToCalendarInvite(messageID: "m1", response: .accepted)
        }
    }

    @Test("mock backend exposes provider extension services when capabilities allow them")
    func mockBackendExposesProviderExtensionServices() async throws {
        let backend = MockBackend(capabilities: [.autoReply, .serverRules, .providerSyncHealth])
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)

        let autoReply = try #require(backend.extensionService(AutoReplyManaging.self))
        let savedResponder = try await autoReply.saveVacationResponder(
            VacationResponderDraft(name: "Holiday", isEnabled: true, message: "Back Monday."),
            sourceID: sourceID
        )
        #expect(savedResponder.isEnabled)
        let disabledResponder = try await autoReply.saveVacationResponder(
            VacationResponderDraft(id: savedResponder.id, name: "Holiday", isEnabled: false, message: "Back Tuesday."),
            sourceID: sourceID
        )
        #expect(!disabledResponder.isEnabled)
        #expect(disabledResponder.message == "Back Tuesday.")
        #expect(try await autoReply.vacationResponderSettings(for: sourceID) == [disabledResponder])
        try await autoReply.deleteVacationResponder(id: disabledResponder.id, sourceID: sourceID)
        #expect(try await autoReply.vacationResponderSettings(for: sourceID).isEmpty)

        let serverRules = try #require(backend.extensionService(ServerRuleManaging.self))
        let savedRule = try await serverRules.saveServerRule(
            ServerRule(
                id: "rule-1",
                name: "Receipts",
                isEnabled: true,
                conditions: [.senderContains("store@example.org")],
                actions: [.moveToFolder(id: "archive-receipts")]
            ),
            sourceID: sourceID
        )
        #expect(try await serverRules.serverRules(for: sourceID) == [savedRule])
        let secondRule = try await serverRules.saveServerRule(
            ServerRule(
                id: "rule-2",
                name: "Newsletters",
                isEnabled: false,
                conditions: [.subjectContains("newsletter")],
                actions: [.archive]
            ),
            sourceID: sourceID
        )
        try await serverRules.reorderServerRules(ids: [secondRule.id, savedRule.id], sourceID: sourceID)
        #expect(try await serverRules.serverRules(for: sourceID).map(\.id) == [secondRule.id, savedRule.id])
        try await serverRules.deleteServerRule(id: savedRule.id, sourceID: sourceID)
        #expect(try await serverRules.serverRules(for: sourceID).map(\.id) == [secondRule.id])

        let contacts = try #require(backend.extensionService(ContactLookupProviding.self))
        let contactResults = try await contacts.contacts(matching: ContactLookupQuery(text: "sigrid", sourceID: sourceID))
        #expect(contactResults.map(\.email) == ["sigrid.moen@example.org"])

        let health = try #require(backend.extensionService(SyncHealthReporting.self))
        let initialHealth = await health.syncHealth(for: sourceID)
        #expect(initialHealth.state == .healthy)
        #expect(initialHealth.localSearchIndexMetrics?.indexedHeaderCount ?? 0 > 0)
        #expect(initialHealth.localSearchIndexMetrics?.cachedBodyCount ?? 0 > 0)

        let repair = try #require(backend.extensionService(SyncHealthRepairing.self))
        try await repair.resetLocalCacheAndIndex(for: sourceID)
        let resetHealth = await health.syncHealth(for: sourceID)
        #expect(resetHealth.indexStatus == .notBuilt)
        #expect(resetHealth.localSearchIndexMetrics?.indexedHeaderCount == 0)
        try await repair.retrySync(for: sourceID)
        let retriedHealth = await health.syncHealth(for: sourceID)
        #expect(retriedHealth.state == .healthy)
        #expect(retriedHealth.localSearchIndexMetrics?.indexedHeaderCount == initialHealth.localSearchIndexMetrics?
            .indexedHeaderCount)
    }

    @Test("mock backend hides unavailable provider mutation services")
    func mockBackendHidesUnavailableProviderMutationServices() {
        let backend = MockBackend(capabilities: [])

        #expect(backend.extensionService(AutoReplyManaging.self) == nil)
        #expect(backend.extensionService(ServerRuleManaging.self) == nil)
        #expect(MockBackend(contacts: []).extensionService(ContactLookupProviding.self) == nil)
        #expect(backend.extensionService(SyncHealthReporting.self) != nil)
        #expect(backend.extensionService(SyncHealthRepairing.self) != nil)
    }

    @Test("contact lookup filters by source and respects limits")
    func contactLookupFiltersBySourceAndLimits() async throws {
        let account = BrevAccount(id: "account", displayName: "Account", emailAddress: "me@example.org")
        let sourceA = MailSourceID(accountID: account.id, mailboxID: "a")
        let sourceB = MailSourceID(accountID: account.id, mailboxID: "b")
        let backend = MockBackend(
            account: account,
            mailboxes: [
                Mailbox(id: "a", email: "a@example.org", displayName: "A", isPrimary: true),
                Mailbox(id: "b", email: "b@example.org", displayName: "B")
            ],
            contacts: [
                ContactLookupResult(id: "a-1", displayName: "Ada Alpha", email: "ada.alpha@example.org", sourceID: sourceA),
                ContactLookupResult(id: "a-2", displayName: "Ada Beta", email: "ada.beta@example.org", sourceID: sourceA),
                ContactLookupResult(id: "b-1", displayName: "Ada Other", email: "ada.other@example.org", sourceID: sourceB)
            ]
        )

        let contacts = try #require(backend.extensionService(ContactLookupProviding.self))
        let results = try await contacts.contacts(matching: ContactLookupQuery(text: "ada", sourceID: sourceA, limit: 1))

        #expect(results.map(\.id) == ["a-1"])
    }

    @Test("save inserts a readable draft into Drafts")
    func saveInsertsReadableDraftIntoDrafts() async throws {
        let backend = MockBackend()
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let draft = Draft(
            id: "local-draft",
            to: [Correspondent(name: "Alex Berg", email: "alex@example.org")],
            subject: "Saved demo draft",
            htmlBody: "Draft body from the desktop app."
        )

        let saved = try await backend.save(draft: draft)

        let draftID = try #require(saved.remoteID)
        #expect(draftID == "draft-local-draft")
        let (headers, _) = try await backend.messages(in: drafts, pageToken: nil)
        let header = try #require(headers.first { $0.id == draftID })
        #expect(header.folderID == drafts.id)
        #expect(header.subject == draft.subject)
        #expect(header.snippet == draft.htmlBody)
        #expect(header.to == draft.to)

        let body = try await backend.body(for: draftID)
        #expect(body.plainText == draft.htmlBody)
    }

    @Test("save updates an existing draft instead of duplicating it")
    func saveUpdatesExistingDraft() async throws {
        let backend = MockBackend()
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let first = try await backend.save(draft: Draft(
            id: "editable",
            subject: "First",
            htmlBody: "First body"
        ))
        let draftID = try #require(first.remoteID)

        let updated = try await backend.save(draft: Draft(
            id: "editable",
            remoteID: draftID,
            subject: "Second",
            htmlBody: "Second body"
        ))

        #expect(updated.remoteID == draftID)
        let (headers, _) = try await backend.messages(in: drafts, pageToken: nil)
        let matches = headers.filter { $0.id == draftID }
        #expect(matches.count == 1)
        #expect(matches.first?.subject == "Second")
        let body = try await backend.body(for: draftID)
        #expect(body.plainText == "Second body")
    }

    @Test("discard removes a saved draft")
    func discardRemovesSavedDraft() async throws {
        let backend = MockBackend()
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let saved = try await backend.save(draft: Draft(
            id: "discard-me",
            subject: "Discard",
            htmlBody: "Discard body"
        ))
        let draftID = try #require(saved.remoteID)

        try await backend.discard(draftID: draftID)

        let (headers, _) = try await backend.messages(in: drafts, pageToken: nil)
        #expect(!headers.contains { $0.id == draftID })
        let updatedDrafts = try #require(await backend.folders().first(where: { $0.id == drafts.id }))
        #expect(updatedDrafts.totalCount == drafts.totalCount)
    }

    @Test("send removes a saved draft from Drafts")
    func sendRemovesSavedDraftFromDrafts() async throws {
        let backend = MockBackend()
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let saved = try await backend.save(draft: Draft(
            id: "send-me",
            to: [Correspondent(email: "maja@example.org")],
            subject: "Send saved draft",
            htmlBody: "Send body"
        ))
        let draftID = try #require(saved.remoteID)

        _ = try await backend.send(draft: saved)

        let (draftHeaders, _) = try await backend.messages(in: drafts, pageToken: nil)
        #expect(!draftHeaders.contains { $0.id == draftID })
        let updatedDrafts = try #require(await backend.folders().first(where: { $0.id == drafts.id }))
        #expect(updatedDrafts.totalCount == drafts.totalCount)
    }

    @Test("mock attachment upload returns ids usable on saved drafts")
    func uploadAttachmentReturnsIDUsableOnSavedDrafts() async throws {
        let backend = MockBackend()
        let attachmentID = try await backend.uploadAttachment(
            draftID: "draft-with-attachment",
            data: Data("hello".utf8),
            filename: "hello.txt",
            mimeType: "text/plain"
        )

        let saved = try await backend.save(draft: Draft(
            id: "with-attachment",
            remoteID: "draft-with-attachment",
            subject: "Attachment",
            htmlBody: "Attachment body",
            attachmentIDs: [attachmentID]
        ))

        let draftID = try #require(saved.remoteID)
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let (headers, _) = try await backend.messages(in: drafts, pageToken: nil)
        let header = try #require(headers.first { $0.id == draftID })
        #expect(header.hasAttachments)
    }

    @Test("uploaded attachment bytes can be downloaded from saved drafts")
    func uploadedAttachmentBytesCanBeDownloadedFromSavedDrafts() async throws {
        let backend = MockBackend()
        let data = Data("hello attachment".utf8)
        let attachmentID = try await backend.uploadAttachment(
            draftID: "draft-download",
            data: data,
            filename: "hello.txt",
            mimeType: "text/plain"
        )
        let saved = try await backend.save(draft: Draft(
            id: "draft-download",
            remoteID: "draft-download",
            subject: "Attachment",
            htmlBody: "Attachment body",
            attachmentIDs: [attachmentID]
        ))
        let draftID = try #require(saved.remoteID)
        let body = try await backend.body(for: draftID)
        let attachment = try #require(body.attachments.first)

        let downloaded = try await backend.downloadAttachment(attachment)

        #expect(downloaded == data)
    }

    @Test("sent messages retain downloadable uploaded attachments")
    func sentMessagesRetainDownloadableUploadedAttachments() async throws {
        let backend = MockBackend()
        let data = Data("sent attachment".utf8)
        let attachmentID = try await backend.uploadAttachment(
            draftID: "sent-download",
            data: data,
            filename: "sent.txt",
            mimeType: "text/plain"
        )
        let result = try await backend.send(draft: Draft(
            id: "sent-download",
            to: [Correspondent(email: "alex@example.org")],
            subject: "Sent attachment",
            htmlBody: "Sent body",
            attachmentIDs: [attachmentID]
        ))
        let sentID = try #require(result.sentMessageID)
        let body = try await backend.body(for: sentID)
        let attachment = try #require(body.attachments.first)

        let downloaded = try await backend.downloadAttachment(attachment)

        #expect(downloaded == data)
    }

    @Test("send inserts the message into Sent and returns readable body")
    func sendInsertsMessageIntoSentAndStoresBody() async throws {
        let backend = MockBackend()
        let sent = try #require(await backend.folders().first(where: { $0.role == .sent }))
        let draft = Draft(
            id: "draft-1",
            to: [Correspondent(name: "Maja Holm", email: "maja@example.org")],
            subject: "Desktop demo",
            htmlBody: "Hello from the mock desktop app."
        )

        let result = try await backend.send(draft: draft)

        let sentID = try #require(result.sentMessageID)
        let (headers, _) = try await backend.messages(in: sent, pageToken: nil)
        let sentHeader = try #require(headers.first { $0.id == sentID })
        #expect(sentHeader.folderID == sent.id)
        #expect(sentHeader.from.email == backend.account.emailAddress)
        #expect(sentHeader.to == draft.to)
        #expect(sentHeader.subject == draft.subject)
        #expect(sentHeader.snippet == draft.htmlBody)
        #expect(sentHeader.isRead)

        let body = try await backend.body(for: sentID)
        #expect(body.messageID == sentID)
        #expect(body.plainText == draft.htmlBody)
    }

    @Test("send updates Sent folder total count")
    func sendUpdatesSentFolderTotalCount() async throws {
        let backend = MockBackend()
        let sent = try #require(await backend.folders().first(where: { $0.role == .sent }))

        _ = try await backend.send(draft: Draft(
            id: "draft-count",
            to: [Correspondent(email: "alex@example.org")],
            subject: "Count me",
            htmlBody: "Count body"
        ))

        let updatedSent = try #require(await backend.folders().first(where: { $0.id == sent.id }))
        #expect(updatedSent.totalCount == sent.totalCount + 1)
        #expect(updatedSent.unreadCount == 0)
    }

    @Test("send emits messagesAdded for the Sent folder")
    func sendEmitsMessagesAddedForSent() async throws {
        let backend = MockBackend()
        let sent = try #require(await backend.folders().first(where: { $0.role == .sent }))
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        let result = try await backend.send(draft: Draft(
            id: "draft-2",
            to: [Correspondent(email: "alex@example.org")],
            subject: "Event",
            htmlBody: "Event body"
        ))

        let event = try await nextEvent(from: stream)
        if case .messagesAdded(folderID: let folderID, messageIDs: let ids) = event {
            #expect(folderID == sent.id)
            #expect(ids == [result.sentMessageID])
        } else {
            Issue.record("expected messagesAdded event, got \(String(describing: event))")
        }
    }

    @Test("outgoing headers use the active mailbox identity")
    func outgoingHeadersUseActiveMailboxIdentity() async throws {
        let backend = MockBackend()
        let secondary = try #require(try await backend.mailboxes().first { !$0.isPrimary })
        try await backend.switchMailbox(id: secondary.id)
        let drafts = try #require(await backend.folders().first(where: { $0.role == .drafts }))
        let sent = try #require(await backend.folders().first(where: { $0.role == .sent }))

        let saved = try await backend.save(draft: Draft(
            id: "secondary-draft",
            subject: "Secondary draft",
            htmlBody: "Secondary draft body"
        ))
        let sentResult = try await backend.send(draft: Draft(
            id: "secondary-send",
            to: [Correspondent(email: "alex@example.org")],
            subject: "Secondary send",
            htmlBody: "Secondary send body"
        ))

        let savedID = try #require(saved.remoteID)
        let sentID = try #require(sentResult.sentMessageID)
        let (draftHeaders, _) = try await backend.messages(in: drafts, pageToken: nil)
        let (sentHeaders, _) = try await backend.messages(in: sent, pageToken: nil)
        let draftHeader = try #require(draftHeaders.first { $0.id == savedID })
        let sentHeader = try #require(sentHeaders.first { $0.id == sentID })
        #expect(draftHeader.from.email == secondary.email)
        #expect(sentHeader.from.email == secondary.email)
    }

    @Test("send reply marks original message answered and emits update")
    func sendReplyMarksOriginalMessageAnsweredAndEmitsUpdate() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let original = try #require(headers.first(where: { !$0.isAnswered }))
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        _ = try await backend.send(draft: Draft(
            id: "reply-send",
            inReplyToMessageID: original.id,
            to: [original.from],
            subject: "Re: \(original.subject)",
            htmlBody: "Thanks for the update."
        ))

        let event = try await nextEvent(from: stream) {
            if case .messagesUpdated(folderID: inbox.id, messageIDs: [original.id]) = $0 {
                return true
            }
            return false
        }
        #expect(event != nil)
        let (updatedHeaders, _) = try await backend.messages(in: inbox, pageToken: nil)
        let updatedOriginal = try #require(updatedHeaders.first { $0.id == original.id })
        #expect(updatedOriginal.isAnswered)
    }

    @Test("send forward marks original message forwarded and emits update")
    func sendForwardMarksOriginalMessageForwardedAndEmitsUpdate() async throws {
        let backend = MockBackend()
        let inbox = try #require(await backend.folders().first(where: { $0.role == .inbox }))
        let (headers, _) = try await backend.messages(in: inbox, pageToken: nil)
        let original = try #require(headers.first(where: { !$0.isForwarded }))
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        _ = try await backend.send(draft: Draft(
            id: "forward-send",
            forwardedMessageID: original.id,
            to: [Correspondent(email: "maja@example.org")],
            subject: "Fwd: \(original.subject)",
            htmlBody: "Forwarding this along."
        ))

        let event = try await nextEvent(from: stream) {
            if case .messagesUpdated(folderID: inbox.id, messageIDs: [original.id]) = $0 {
                return true
            }
            return false
        }
        #expect(event != nil)
        let (updatedHeaders, _) = try await backend.messages(in: inbox, pageToken: nil)
        let updatedOriginal = try #require(updatedHeaders.first { $0.id == original.id })
        #expect(updatedOriginal.isForwarded)
    }

    @Test("capabilities are populated for previews")
    func capabilitiesArePopulatedForPreviews() {
        let backend = MockBackend()
        #expect(backend.capabilities.contains(.serverSideSearch))
        #expect(backend.capabilities.contains(.serverSideThreading))
        #expect(backend.capabilities.contains(.oauthAuth))
    }

    @Test("preview backend exposes and switches multiple mailboxes")
    func previewBackendExposesAndSwitchesMultipleMailboxes() async throws {
        let backend = MockBackend()
        let mailboxes = try await backend.mailboxes()
        let primary = try #require(mailboxes.first { $0.isPrimary })
        let secondary = try #require(mailboxes.first { !$0.isPrimary })
        let primaryInbox = try #require(await backend.folders().first { $0.role == .inbox })
        let (primaryHeaders, _) = try await backend.messages(in: primaryInbox, pageToken: nil)
        let stream = backend.subscribeToChanges()
        try await Task.sleep(nanoseconds: 10_000_000)

        let initial = try await backend.currentMailbox()
        try await backend.switchMailbox(id: secondary.id)
        let secondaryInbox = try #require(await backend.folders().first { $0.role == .inbox })
        let (secondaryHeaders, _) = try await backend.messages(in: secondaryInbox, pageToken: nil)
        try await backend.switchMailbox(id: primary.id)
        let restoredInbox = try #require(await backend.folders().first { $0.role == .inbox })
        let (restoredHeaders, _) = try await backend.messages(in: restoredInbox, pageToken: nil)

        #expect(mailboxes.count > 1)
        #expect(initial.id == primary.id)
        #expect(primaryHeaders.map(\.id) != secondaryHeaders.map(\.id))
        #expect(secondaryHeaders.allSatisfy { header in
            header.to.contains { $0.email == secondary.email }
        })
        #expect(restoredHeaders.map(\.id) == primaryHeaders.map(\.id))
        let event = try await nextEvent(from: stream)
        #expect(event == .mailboxChanged(mailboxID: secondary.id))
    }

    @Test("source-scoped reads do not switch the active mailbox")
    func sourceScopedReadsDoNotSwitchActiveMailbox() async throws {
        let backend = MockBackend()
        let mailboxes = try await backend.mailboxes()
        let primary = try #require(mailboxes.first { $0.isPrimary })
        let secondary = try #require(mailboxes.first { !$0.isPrimary })
        let primarySource = backend.sourceID(for: primary)
        let secondarySource = backend.sourceID(for: secondary)
        let initialMailbox = try await backend.currentMailbox()

        let primaryInbox = try #require(
            try await backend.folders(in: primarySource).first { $0.role == .inbox }
        )
        let secondaryInbox = try #require(
            try await backend.folders(in: secondarySource).first { $0.role == .inbox }
        )
        let (primaryHeaders, _) = try await backend.messages(
            in: primaryInbox,
            sourceID: primarySource,
            pageToken: nil
        )
        let (secondaryHeaders, _) = try await backend.messages(
            in: secondaryInbox,
            sourceID: secondarySource,
            pageToken: nil
        )

        #expect(initialMailbox.id == primary.id)
        #expect(try await backend.currentMailbox().id == initialMailbox.id)
        #expect(primaryHeaders.map(\.id) != secondaryHeaders.map(\.id))
        #expect(secondaryHeaders.allSatisfy { header in
            header.to.contains { $0.email == secondary.email }
        })
    }

    @Test("source-scoped mutations only affect the requested mailbox")
    func sourceScopedMutationsOnlyAffectRequestedMailbox() async throws {
        let backend = MockBackend()
        let mailboxes = try await backend.mailboxes()
        let primary = try #require(mailboxes.first { $0.isPrimary })
        let secondary = try #require(mailboxes.first { !$0.isPrimary })
        let primarySource = backend.sourceID(for: primary)
        let secondarySource = backend.sourceID(for: secondary)
        let primaryInbox = try #require(
            try await backend.folders(in: primarySource).first { $0.role == .inbox }
        )
        let secondaryInbox = try #require(
            try await backend.folders(in: secondarySource).first { $0.role == .inbox }
        )
        let (primaryHeaders, _) = try await backend.messages(
            in: primaryInbox,
            sourceID: primarySource,
            pageToken: nil
        )
        let (secondaryHeadersBefore, _) = try await backend.messages(
            in: secondaryInbox,
            sourceID: secondarySource,
            pageToken: nil
        )
        let unread = try #require(primaryHeaders.first { !$0.isRead })

        try await backend.setRead(true, for: [unread.id], sourceID: primarySource)

        let (updatedPrimaryHeaders, _) = try await backend.messages(
            in: primaryInbox,
            sourceID: primarySource,
            pageToken: nil
        )
        let (secondaryHeadersAfter, _) = try await backend.messages(
            in: secondaryInbox,
            sourceID: secondarySource,
            pageToken: nil
        )
        let updated = try #require(updatedPrimaryHeaders.first { $0.id == unread.id })
        #expect(updated.isRead)
        #expect(secondaryHeadersAfter == secondaryHeadersBefore)
        #expect(try await backend.currentMailbox().id == primary.id)
    }
}

private enum EventTimeout: Error {
    case timedOut
}

private func nextEvent(
    from stream: AsyncStream<MailEvent>,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async throws -> MailEvent? {
    try await nextEvent(from: stream, timeoutNanoseconds: timeoutNanoseconds) { _ in true }
}

private func nextEvent(
    from stream: AsyncStream<MailEvent>,
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    matching predicate: @escaping @Sendable (MailEvent) -> Bool
) async throws -> MailEvent? {
    try await withThrowingTaskGroup(of: MailEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            while let event = await iterator.next() {
                if predicate(event) {
                    return event
                }
            }
            return nil
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw EventTimeout.timedOut
        }

        let event = try await group.next()
        group.cancelAll()
        return event ?? nil
    }
}
