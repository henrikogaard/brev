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

@Suite("Mock scheduled sends")
struct MockScheduledSendTests {
    private static let account = BrevAccount(
        id: "mock-schedule-account",
        displayName: "Mock",
        emailAddress: "primary@example.test"
    )
    private static let sourceA = MailSourceID(accountID: account.id, mailboxID: "mailbox-a")
    private static let sourceB = MailSourceID(accountID: account.id, mailboxID: "mailbox-b")
    private static let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("scheduled-send services are enabled by default and can be disabled")
    func schedulingServiceAvailability() {
        let enabled = MockBackend(automaticDeliveryEnabled: false)
        let disabled = MockBackend(supportsScheduledSend: false, automaticDeliveryEnabled: false)
        #expect(enabled.extensionService(ScheduledSendManaging.self) != nil)
        #expect(enabled.extensionService(ScheduledSendEditing.self) != nil)
        #expect(disabled.extensionService(ScheduledSendManaging.self) == nil)
        #expect(disabled.extensionService(ScheduledSendEditing.self) == nil)
    }

    @Test("explicit scheduling queues source-owned colliding drafts without sending immediately")
    func schedulingUsesOpaqueSourceOwnedIdentifiers() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MockScheduledSendClock(Self.now)
        let dueAt = Self.now.addingTimeInterval(60)
        let backend = Self.backend(persistenceDirectory: directory, now: { clock.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendEditing.self))

        let firstAttachmentID = try await backend.uploadAttachment(
            draftID: "same-draft",
            data: Data([1]),
            filename: "first.txt",
            mimeType: "text/plain",
            sourceID: Self.sourceA
        )
        let secondAttachmentID = try await backend.uploadAttachment(
            draftID: "same-draft",
            data: Data([2]),
            filename: "second.txt",
            mimeType: "text/plain",
            sourceID: Self.sourceB
        )
        #expect(firstAttachmentID != secondAttachmentID)

        let first = try await backend.save(draft: Draft(
            id: "same-draft",
            remoteID: "draft-same-draft",
            subject: "A",
            htmlBody: "A body",
            attachmentIDs: [firstAttachmentID]
        ), sourceID: Self.sourceA)
        let second = try await backend.save(draft: Draft(
            id: "same-draft",
            remoteID: "draft-same-draft",
            subject: "B",
            htmlBody: "B body",
            attachmentIDs: [secondAttachmentID]
        ), sourceID: Self.sourceB)
        _ = try await backend.save(
            draft: Draft(id: "future-autosave", scheduledFor: Self.now.addingTimeInterval(60)),
            sourceID: Self.sourceA
        )
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let events = backend.subscribeToChanges()

        var scheduledFirst = first
        scheduledFirst.scheduledFor = dueAt
        var scheduledSecond = second
        scheduledSecond.scheduledFor = dueAt
        let firstResult = try await backend.send(draft: scheduledFirst, sourceID: Self.sourceA)
        let secondResult = try await backend.send(draft: scheduledSecond, sourceID: Self.sourceB)
        let committedQueueEvent = try await nextEvent(from: events) { $0 == .outboxChanged }

        #expect(firstResult.sentMessageID == nil)
        #expect(firstResult.scheduledFor == dueAt)
        #expect(secondResult.sentMessageID == nil)
        #expect(secondResult.scheduledFor == dueAt)
        let entries = scheduler.pendingScheduledSends()
        #expect(entries.count == 2)
        #expect(committedQueueEvent == .outboxChanged)
        #expect(Set(entries.map(\.id)).count == 2)
        #expect(entries.allSatisfy { $0.id != "same-draft" })
        #expect(Set(entries.compactMap(\.sourceID)) == [Self.sourceA, Self.sourceB])
        for entry in entries {
            #expect(try await scheduler.scheduledDraft(id: entry.id).id == "same-draft")
        }

        let firstID = try #require(entries.first { $0.sourceID == Self.sourceA }?.id)
        let secondID = try #require(entries.first { $0.sourceID == Self.sourceB }?.id)
        let editing = try #require(backend.extensionService(ScheduledSendEditing.self))
        #expect(try await backend.draft(for: first.id, sourceID: Self.sourceA)?.subject == "A")
        #expect(try await backend.draft(for: second.id, sourceID: Self.sourceB)?.subject == "B")
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        _ = try journal.transact { records in
            guard let index = records.firstIndex(where: {
                $0.sourceID == Self.sourceB && $0.draftID == "same-draft" && $0.state == .queued
            }),
                let attachment = records[index].attachments.first,
                var draft = records[index].draft else {
                throw MockSendJournalError.invalidFile
            }
            let metadata = attachment.metadata
            records[index].attachments = [MockSendJournalAttachment(
                metadata: Attachment(
                    id: firstAttachmentID,
                    name: metadata.name,
                    mimeType: metadata.mimeType,
                    sizeBytes: metadata.sizeBytes,
                    isInline: metadata.isInline,
                    contentID: metadata.contentID,
                    resource: metadata.resource
                ),
                data: attachment.data,
                draftID: attachment.draftID
            )]
            draft.attachmentIDs = [firstAttachmentID]
            records[index].draft = draft
        }
        try await backend.connect()
        let restoredFirst = try #require(try await backend.draft(for: first.id, sourceID: Self.sourceA))
        let restoredSecond = try #require(try await backend.draft(for: second.id, sourceID: Self.sourceB))
        #expect(restoredFirst.attachmentIDs == [firstAttachmentID])
        #expect(restoredSecond.attachmentIDs == [firstAttachmentID])
        #expect(try await backend.localDraftAttachments(for: restoredFirst, sourceID: Self.sourceA).map(\.data) == [Data([1])])
        #expect(try await backend.localDraftAttachments(for: restoredSecond, sourceID: Self.sourceB).map(\.data) == [Data([2])])
        await #expect(throws: (any Error).self) {
            try await editing.cancelScheduledSend(id: "unknown-schedule-id")
        }
        _ = try await editing.cancelScheduledSend(id: firstID)
        #expect(scheduler.pendingScheduledSends().map(\.id) == [secondID])
        #expect(try await editing.scheduledDraft(id: secondID).subject == "B")
        let canceledFirst = try #require(try await backend.draft(for: first.id, sourceID: Self.sourceA))
        #expect(try await backend.localDraftAttachments(for: canceledFirst, sourceID: Self.sourceA).map(\.data) == [Data([1])])
        clock.advance(to: dueAt)
        await scheduler.deliverDueScheduledSends()
        #expect(scheduler.pendingScheduledSends().isEmpty)

        let sent = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (sentHeaders, _) = try await backend.messages(in: sent, sourceID: Self.sourceA, pageToken: nil)
        #expect(sentHeaders.isEmpty)
        let sentB = try #require(await backend.folders(in: Self.sourceB).first { $0.role == .sent })
        let (sentBHeaders, _) = try await backend.messages(in: sentB, sourceID: Self.sourceB, pageToken: nil)
        let sentBHeader = try #require(sentBHeaders.first { $0.subject == "B" })
        let sentBBody = try await backend.body(for: sentBHeader.id, sourceID: Self.sourceB)
        let sentBAttachment = try #require(sentBBody.attachments.first)
        #expect(sentBAttachment.id == firstAttachmentID)
        #expect(try await backend.downloadAttachment(sentBAttachment, sourceID: Self.sourceB) == Data([2]))

        let reopened = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let reopenedScheduler = try #require(reopened.extensionService(ScheduledSendManaging.self))
        #expect(reopenedScheduler.pendingScheduledSends().isEmpty)
        let reopenedDraft = try #require(try await reopened.draft(for: first.id, sourceID: Self.sourceA))
        #expect(try await reopened.localDraftAttachments(for: reopenedDraft, sourceID: Self.sourceA).map(\.data) == [Data([1])])
        let reopenedSent = try #require(await reopened.folders(in: Self.sourceB).first { $0.role == .sent })
        let (reopenedSentHeaders, _) = try await reopened.messages(in: reopenedSent, sourceID: Self.sourceB, pageToken: nil)
        let reopenedSentHeader = try #require(reopenedSentHeaders.first { $0.subject == "B" })
        let reopenedSentBody = try await reopened.body(for: reopenedSentHeader.id, sourceID: Self.sourceB)
        let reopenedAttachment = try #require(reopenedSentBody.attachments.first)
        #expect(try await reopened.downloadAttachment(reopenedAttachment, sourceID: Self.sourceB) == Data([2]))
    }

    @Test("saving an attachment draft preserves its planned Later date until explicit send")
    func savedAttachmentDraftRetainsPlannedSchedule() async throws {
        let backend = Self.backend(persistenceDirectory: nil, now: { Self.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendEditing.self))
        let scheduledFor = Self.now.addingTimeInterval(3600)
        let attachmentID = try await backend.uploadAttachment(
            draftID: "saved-for-later",
            data: Data([8, 9, 10]),
            filename: "later.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let saved = try await backend.save(draft: Draft(
            id: "saved-for-later",
            htmlBody: "Later body",
            attachmentIDs: [attachmentID],
            scheduledFor: scheduledFor
        ), sourceID: Self.sourceA)

        #expect(saved.scheduledFor == scheduledFor)
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let sentFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (sentBefore, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(sentBefore.isEmpty)

        let result = try await backend.send(draft: saved, sourceID: Self.sourceA)

        #expect(result.sentMessageID == nil)
        #expect(result.scheduledFor == scheduledFor)
        let entry = try #require(scheduler.pendingScheduledSends().first)
        let queued = try await scheduler.scheduledDraft(id: entry.id)
        #expect(queued.scheduledFor == scheduledFor)
        #expect(try await backend.localDraftAttachments(for: queued, sourceID: Self.sourceA).map(\.data) == [Data([8, 9, 10])])

        var canceled = try #require(try await scheduler.cancelScheduledSend(id: entry.id))
        #expect(canceled.scheduledFor == nil)
        let replannedDate = scheduledFor.addingTimeInterval(3600)
        canceled.scheduledFor = replannedDate
        let savedCanceled = try await backend.save(draft: canceled, sourceID: Self.sourceA)
        #expect(savedCanceled.scheduledFor == replannedDate)
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let requeued = try await backend.send(draft: savedCanceled, sourceID: Self.sourceA)
        #expect(requeued.sentMessageID == nil)
        #expect(requeued.scheduledFor == replannedDate)
        let requeuedEntry = try #require(scheduler.pendingScheduledSends().first)
        let requeuedDraft = try await scheduler.scheduledDraft(id: requeuedEntry.id)
        #expect(try await backend.localDraftAttachments(for: requeuedDraft, sourceID: Self.sourceA).map(\.data) == [Data([
            8,
            9,
            10
        ])])
    }

    @Test("the Mock send handler overrides both local sends and scheduled inputs")
    func sendHandlerOverridesScheduledInput() async throws {
        let backend = Self.backend(persistenceDirectory: nil)
        backend.sendHandler = { draft, sourceID in
            SendResult(sentMessageID: "override-\(sourceID?.mailboxID ?? "active")-\(draft.id)")
        }

        let result = try await backend.send(
            draft: Draft(id: "handler-schedule", scheduledFor: Self.now),
            sourceID: Self.sourceA
        )

        #expect(result.sentMessageID == "override-mailbox-a-handler-schedule")
        #expect(backend.pendingScheduledSends().isEmpty)
    }

    @Test("concurrent journal writes preserve colliding source-scoped draft identifiers")
    func concurrentSourceWritesStayIsolated() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstBackend = Self.backend(persistenceDirectory: directory)
        let secondBackend = Self.backend(persistenceDirectory: directory)
        let firstAttachment = try await firstBackend.uploadAttachment(
            draftID: "shared-draft",
            data: Data([1]),
            filename: "first.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let secondAttachment = try await secondBackend.uploadAttachment(
            draftID: "shared-draft",
            data: Data([2]),
            filename: "second.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceB
        )

        async let firstResult = firstBackend.send(draft: Draft(
            id: "shared-draft",
            attachmentIDs: [firstAttachment],
            scheduledFor: Self.now
        ), sourceID: Self.sourceA)
        async let secondResult = secondBackend.send(draft: Draft(
            id: "shared-draft",
            attachmentIDs: [secondAttachment],
            scheduledFor: Self.now
        ), sourceID: Self.sourceB)
        let firstSend = try await firstResult
        let secondSend = try await secondResult
        #expect(firstSend.sentMessageID == nil)
        #expect(secondSend.sentMessageID == nil)

        let restored = Self.backend(persistenceDirectory: directory)
        let entries = try #require(restored.extensionService(ScheduledSendManaging.self)).pendingScheduledSends()
        #expect(entries.count == 2)
        #expect(Set(entries.compactMap(\.sourceID)) == [Self.sourceA, Self.sourceB])
        #expect(Set(entries.map(\.id)).count == 2)
        for entry in entries {
            #expect(try await restored.scheduledDraft(id: entry.id).id == "shared-draft")
        }
        let firstScheduleID = try #require(entries.first { $0.sourceID == Self.sourceA }?.id)
        let secondScheduleID = try #require(entries.first { $0.sourceID == Self.sourceB }?.id)
        let first = try await restored.scheduledDraft(id: firstScheduleID)
        let second = try await restored.scheduledDraft(id: secondScheduleID)
        #expect(first.attachmentIDs != second.attachmentIDs)
        #expect(try await restored.localDraftAttachments(for: first, sourceID: Self.sourceA).map(\.data) == [Data([1])])
        #expect(try await restored.localDraftAttachments(for: second, sourceID: Self.sourceB).map(\.data) == [Data([2])])
    }

    @Test("delivery refreshes durable cancellation from another Mock instance")
    func deliveryDoesNotReviveCrossInstanceCancellation() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let deliveringBackend = Self.backend(persistenceDirectory: directory)
        let deliveringScheduler = try #require(deliveringBackend.extensionService(ScheduledSendManaging.self))
        _ = try await deliveringBackend.send(
            draft: Draft(id: "cross-instance", subject: "Canceled", scheduledFor: Self.now),
            sourceID: Self.sourceA
        )
        let scheduleID = try #require(deliveringScheduler.pendingScheduledSends().first?.id)
        let editingBackend = Self.backend(persistenceDirectory: directory)
        let editingScheduler = try #require(editingBackend.extensionService(ScheduledSendEditing.self))

        _ = try await editingScheduler.cancelScheduledSend(id: scheduleID)
        await deliveringScheduler.deliverDueScheduledSends()

        #expect(deliveringScheduler.pendingScheduledSends().isEmpty)
        let sent = try #require(await deliveringBackend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await deliveringBackend.messages(in: sent, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.isEmpty)
    }

    @Test("reschedule, cancel, restart and later draft edits preserve the canonical payload")
    func editingAndRestartRetainCanonicalDraftAndAttachments() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendEditing.self))
        let attachmentID = try await backend.uploadAttachment(
            draftID: "rich-draft",
            data: Data([0, 1, 2, 255]),
            filename: "payload.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let saved = try await backend.save(draft: Draft(
            id: "rich-draft",
            remoteID: "draft-rich-draft",
            identityID: "identity-1",
            threadID: "thread-1",
            inReplyToMessageID: "parent-message",
            forwardedMessageID: "forwarded-message",
            to: [Correspondent(name: "Ada", email: "ada@example.test")],
            cc: [Correspondent(email: "cc@example.test")],
            bcc: [Correspondent(email: "bcc@example.test")],
            subject: "Rich draft",
            htmlBody: "<p>before</p><blockquote>quoted</blockquote>",
            attachmentIDs: [attachmentID],
            securityMode: .signAndEncrypt,
            quoteBoundary: DraftQuoteBoundary(marker: "quoted", edge: .bottom)
        ), sourceID: Self.sourceA)
        var submitted = saved
        submitted.scheduledFor = Self.now
        let accepted = try await backend.send(draft: submitted, sourceID: Self.sourceA)
        let originalID = try #require(scheduler.pendingScheduledSends().first?.id)
        #expect(originalID != saved.id)
        #expect(accepted.sentMessageID == nil)

        let changedDate = Self.now.addingTimeInterval(3600)
        try await scheduler.rescheduleSend(id: originalID, for: changedDate)
        #expect(scheduler.pendingScheduledSends().first?.id == originalID)
        let reopened = Self.backend(persistenceDirectory: directory)
        let reopenedScheduler = try #require(reopened.extensionService(ScheduledSendEditing.self))
        #expect(reopenedScheduler.pendingScheduledSends().first?.id == originalID)
        let restored = try await reopenedScheduler.scheduledDraft(id: originalID)
        var expected = submitted
        expected.scheduledFor = changedDate
        #expect(restored == expected)
        #expect(try await reopened.localDraftAttachments(for: restored, sourceID: Self.sourceA).map(\.data) == [Data([
            0,
            1,
            2,
            255
        ])])

        let canceled = try #require(try await reopenedScheduler.cancelScheduledSend(id: originalID))
        var expectedCanceled = expected
        expectedCanceled.scheduledFor = nil
        #expect(canceled == expectedCanceled)
        var edited = canceled
        edited.htmlBody = "<p>edited after cancel</p>"
        let savedAgain = try await reopened.save(draft: edited, sourceID: Self.sourceA)
        #expect(savedAgain == edited)
        #expect(try await reopened.localDraftAttachments(for: savedAgain, sourceID: Self.sourceA).map(\.data) == [Data([
            0,
            1,
            2,
            255
        ])])
        try await reopened.discard(draftID: savedAgain.id, sourceID: Self.sourceA)

        let afterDiscard = Self.backend(persistenceDirectory: directory)
        #expect(try await afterDiscard.draft(for: savedAgain.id, sourceID: Self.sourceA) == nil)
        #expect(afterDiscard.extensionService(ScheduledSendManaging.self)?.pendingScheduledSends().isEmpty == true)
    }

    @Test("discarding a queued persistent draft clears its schedule identity")
    func discardQueuedPersistentDraftClearsScheduleIdentity() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let draft = Draft(
            id: "discard-queued",
            subject: "Discard queued draft",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: draft, sourceID: Self.sourceA)

        try await backend.discard(draftID: draft.id, sourceID: Self.sourceA)

        #expect(scheduler.pendingScheduledSends().isEmpty)
        let records = try journal.load()
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.state == .canceled)
        #expect(record.scheduleID == nil)
        #expect(record.draft == nil)
        #expect(record.attachments.isEmpty)
        #expect(record.scheduledFor == nil)

        let restored = Self.backend(
            persistenceDirectory: directory,
            now: { Self.now.addingTimeInterval(7200) },
            automaticDeliveryEnabled: false
        )
        let restoredScheduler = try #require(restored.extensionService(ScheduledSendManaging.self))
        #expect(restoredScheduler.pendingScheduledSends().isEmpty)
        #expect(try await restored.draft(for: draft.id, sourceID: Self.sourceA) == nil)
        await restoredScheduler.deliverDueScheduledSends()
        let sentFolder = try #require(await restored.folders(in: Self.sourceA).first { $0.role == .sent })
        let (sentHeaders, _) = try await restored.messages(
            in: sentFolder,
            sourceID: Self.sourceA,
            pageToken: nil
        )
        #expect(!sentHeaders.contains { $0.subject == draft.subject })
    }

    @Test("discard persistence failure preserves the queued draft and content")
    func failedDiscardPreservesQueuedDraft() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let draft = Draft(
            id: "discard-storage-failure",
            subject: "Keep queued content",
            htmlBody: "Retain this body",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let scheduleID = try #require(scheduler.pendingScheduledSends().first?.id)
        let acceptedJournal = try Data(contentsOf: journal.fileURL)
        try FileManager.default.removeItem(at: directory)

        await #expect(throws: (any Error).self) {
            try await backend.discard(draftID: draft.id, sourceID: Self.sourceA)
        }
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try acceptedJournal.write(to: journal.fileURL, options: .atomic)
        try await backend.connect()
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])
        let restoredDraft = try #require(try await backend.draft(for: draft.id, sourceID: Self.sourceA))
        #expect(restoredDraft.htmlBody == draft.htmlBody)
    }

    @Test("a canceled durable draft upload does not reuse a retained attachment id")
    func canceledDraftAttachmentIdentityDoesNotCollide() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let editor = try #require(backend.extensionService(ScheduledSendEditing.self))
        let firstID = try await backend.uploadAttachment(
            draftID: "attachment-reuse",
            data: Data([1]),
            filename: "removed.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let retainedID = try await backend.uploadAttachment(
            draftID: "attachment-reuse",
            data: Data([2]),
            filename: "retained.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let queuedDraft = Draft(
            id: "attachment-reuse",
            subject: "Keep attachment bytes",
            attachmentIDs: [firstID, retainedID],
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: queuedDraft, sourceID: Self.sourceA)
        let scheduleID = try #require(editor.pendingScheduledSends().first?.id)
        let canceled = try #require(try await editor.cancelScheduledSend(id: scheduleID))
        var edited = canceled
        edited.attachmentIDs = [retainedID]
        let saved = try await backend.save(draft: edited, sourceID: Self.sourceA)

        let addedID = try await backend.uploadAttachment(
            draftID: saved.id,
            data: Data([3]),
            filename: "added.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )

        #expect(addedID != retainedID)
        var savedWithBoth = saved
        savedWithBoth.attachmentIDs = [retainedID, addedID]
        savedWithBoth = try await backend.save(draft: savedWithBoth, sourceID: Self.sourceA)
        #expect(try await backend.localDraftAttachments(for: savedWithBoth, sourceID: Self.sourceA).map(\.data) == [
            Data([2]),
            Data([3]),
        ])

        let reopened = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let restored = try #require(try await reopened.draft(for: savedWithBoth.id, sourceID: Self.sourceA))
        #expect(restored.attachmentIDs == [retainedID, addedID])
        #expect(try await reopened.localDraftAttachments(for: restored, sourceID: Self.sourceA).map(\.data) == [
            Data([2]),
            Data([3]),
        ])
    }

    @Test("trash and permanent deletion remove queued drafts without restoring them")
    func deletingQueuedDraftsDoesNotResurrectThem() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let deletedDraft = Draft(
            id: "delete-to-trash",
            subject: "Delete to Trash",
            htmlBody: "<p>Trash draft content</p>",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        let movedDraft = Draft(
            id: "move-to-trash",
            subject: "Move to Trash",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        let sourceBDraft = Draft(
            id: deletedDraft.id,
            subject: "Source B copy",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: deletedDraft, sourceID: Self.sourceA)
        _ = try await backend.send(draft: movedDraft, sourceID: Self.sourceA)
        _ = try await backend.send(draft: sourceBDraft, sourceID: Self.sourceB)
        let deletedID = "draft-\(deletedDraft.id)"
        let movedID = "draft-\(movedDraft.id)"
        let trash = Folder(id: "trash", name: "Trash", role: .trash)

        try await backend.delete(messageIDs: [deletedID], sourceID: Self.sourceA)
        #expect(scheduler.pendingScheduledSends().count == 2)
        #expect(scheduler.pendingScheduledSends().contains { $0.sourceID == Self.sourceB && $0.draftID == sourceBDraft.id })
        try await backend.move(messageIDs: [movedID], to: trash, sourceID: Self.sourceA)
        #expect(scheduler.pendingScheduledSends().count == 1)
        #expect(scheduler.pendingScheduledSends().first?.sourceID == Self.sourceB)
        let (trashed, _) = try await backend.messages(in: trash, sourceID: Self.sourceA, pageToken: nil)
        #expect(Set(trashed.map(\.id)) == Set([deletedID, movedID]))
        let trashedBody = try await backend.body(for: deletedID, sourceID: Self.sourceA)
        #expect(trashedBody.html == deletedDraft.htmlBody)

        try await backend.delete(messageIDs: [deletedID], sourceID: Self.sourceA)
        let (afterPermanentDelete, _) = try await backend.messages(in: trash, sourceID: Self.sourceA, pageToken: nil)
        #expect(afterPermanentDelete.map(\.id) == [movedID])
        let remainingRecord = try #require(journal.load().first)
        #expect(remainingRecord.sourceID == Self.sourceB)
        #expect(remainingRecord.draftID == sourceBDraft.id)

        let reopened = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let reopenedScheduler = try #require(reopened.extensionService(ScheduledSendManaging.self))
        #expect(reopenedScheduler.pendingScheduledSends().count == 1)
        #expect(reopenedScheduler.pendingScheduledSends().first?.sourceID == Self.sourceB)
        #expect(try await reopened.draft(for: deletedDraft.id, sourceID: Self.sourceA) == nil)
        #expect(try await reopened.draft(for: deletedDraft.id, sourceID: Self.sourceB)?.subject == sourceBDraft.subject)
        #expect(try await reopened.draft(for: movedDraft.id, sourceID: Self.sourceA) == nil)
        let drafts = try #require(await reopened.folders(in: Self.sourceA).first { $0.role == .drafts })
        let (restoredDrafts, _) = try await reopened.messages(in: drafts, sourceID: Self.sourceA, pageToken: nil)
        #expect(!restoredDrafts.contains { $0.id == deletedID || $0.id == movedID })
        let sourceBDrafts = try #require(await reopened.folders(in: Self.sourceB).first { $0.role == .drafts })
        let (sourceBHeaders, _) = try await reopened.messages(in: sourceBDrafts, sourceID: Self.sourceB, pageToken: nil)
        #expect(sourceBHeaders.contains { $0.id == deletedID && $0.subject == sourceBDraft.subject })
    }

    @Test("delete persistence failure preserves the queued draft and content")
    func failedDeletePreservesQueuedDraft() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let draft = Draft(
            id: "delete-storage-failure",
            subject: "Keep delete content",
            htmlBody: "<p>Retain this body</p>",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let scheduleID = try #require(scheduler.pendingScheduledSends().first?.id)
        let acceptedJournal = try Data(contentsOf: journal.fileURL)
        try FileManager.default.removeItem(at: directory)

        await #expect(throws: (any Error).self) {
            try await backend.delete(messageIDs: ["draft-\(draft.id)"], sourceID: Self.sourceA)
        }
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try acceptedJournal.write(to: journal.fileURL, options: .atomic)
        try await backend.connect()
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])
        let drafts = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .drafts })
        let (headers, _) = try await backend.messages(in: drafts, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.contains { $0.id == "draft-\(draft.id)" })
        let preservedDraft = try #require(try await backend.draft(for: draft.id, sourceID: Self.sourceA))
        #expect(preservedDraft.htmlBody == draft.htmlBody)
    }

    @Test("unscoped delete and Trash move propagate journal failures")
    func failedUnscopedDeleteAndTrashMovePreserveQueuedDraft() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, automaticDeliveryEnabled: false)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let mailbox = try await backend.currentMailbox()
        let sourceID = backend.sourceID(for: mailbox)
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let draft = Draft(
            id: "unscoped-delete-storage-failure",
            subject: "Keep unscoped content",
            htmlBody: "<p>Retain this body</p>",
            scheduledFor: Self.now.addingTimeInterval(3600)
        )
        _ = try await backend.send(draft: draft, sourceID: sourceID)
        let messageID = "draft-\(draft.id)"
        let scheduleID = try #require(scheduler.pendingScheduledSends().first?.id)
        let acceptedJournal = try Data(contentsOf: journal.fileURL)
        let originalFolders = try await backend.folders(in: sourceID)
        try FileManager.default.removeItem(at: directory)

        await #expect(throws: (any Error).self) {
            try await backend.delete(messageIDs: [messageID])
        }
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])
        await #expect(throws: (any Error).self) {
            try await backend.move(
                messageIDs: [messageID],
                to: Folder(id: "trash", name: "Trash", role: .trash)
            )
        }
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try acceptedJournal.write(to: journal.fileURL, options: .atomic)
        try await backend.connect()
        #expect(scheduler.pendingScheduledSends().map(\.id) == [scheduleID])
        let foldersAfterRecovery = try await backend.folders(in: sourceID)
        #expect(foldersAfterRecovery == originalFolders)
        #expect(!foldersAfterRecovery.contains { $0.role == .trash })
        let drafts = try #require(await backend.folders(in: sourceID).first { $0.role == .drafts })
        let (draftHeaders, _) = try await backend.messages(in: drafts, sourceID: sourceID, pageToken: nil)
        #expect(draftHeaders.contains { $0.id == messageID })
        let preservedDraft = try #require(try await backend.draft(for: draft.id, sourceID: sourceID))
        #expect(preservedDraft.htmlBody == draft.htmlBody)
    }

    @Test("due delivery commits exact Sent metadata once and restores it without resending")
    func dueDeliveryPersistsExactSentMessage() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, now: { Self.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let parentResult = try await backend.send(draft: Draft(
            id: "parent",
            to: [Correspondent(email: "recipient@example.test")],
            subject: "Parent",
            htmlBody: "<p>Parent body</p>"
        ), sourceID: Self.sourceA)
        let parentID = try #require(parentResult.sentMessageID)
        let parentFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (parentHeaders, _) = try await backend.messages(in: parentFolder, sourceID: Self.sourceA, pageToken: nil)
        let parent = try #require(parentHeaders.first { $0.id == parentID })
        let attachmentID = try await backend.uploadAttachment(
            draftID: "scheduled-reply",
            data: Data("exact bytes".utf8),
            filename: "exact.txt",
            mimeType: "text/plain",
            sourceID: Self.sourceA
        )
        let draft = Draft(
            id: "scheduled-reply",
            inReplyToMessageID: parent.id,
            to: [Correspondent(email: "recipient@example.test")],
            subject: "Reply",
            htmlBody: "<p>Exact reply</p>",
            attachmentIDs: [attachmentID],
            scheduledFor: Self.now
        )
        let result = try await backend.send(draft: draft, sourceID: Self.sourceA)
        #expect(result.sentMessageID == nil)
        async let firstDelivery: Void = scheduler.deliverDueScheduledSends()
        async let secondDelivery: Void = scheduler.deliverDueScheduledSends()
        _ = await (firstDelivery, secondDelivery)

        let (sentHeaders, _) = try await backend.messages(in: parentFolder, sourceID: Self.sourceA, pageToken: nil)
        let sent = try #require(sentHeaders.first { $0.subject == "Reply" })
        let expectedMessageID = MIMEMessageBuilder.messageIDHeaderValue(
            draftID: draft.id,
            fromEmail: "primary@example.test"
        )
        #expect(sent.date == Self.now)
        #expect(sent.messageID == expectedMessageID)
        #expect(sent.inReplyTo == parent.messageID)
        #expect(sent.references == [parent.messageID].compactMap { $0 })
        #expect(scheduler.pendingScheduledSends().isEmpty)
        #expect(sentHeaders.first { $0.id == parent.id }?.isAnswered == true)
        let sentBody = try await backend.body(for: sent.id, sourceID: Self.sourceA)
        #expect(sentBody.html == draft.htmlBody)
        #expect(try await backend
            .downloadAttachment(#require(sentBody.attachments.first), sourceID: Self.sourceA) == Data("exact bytes".utf8))

        let restored = Self.backend(persistenceDirectory: directory, now: { Self.now.addingTimeInterval(50000) })
        let (restoredHeaders, _) = try await restored.messages(in: parentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(restoredHeaders.filter { $0.messageID == expectedMessageID }.count == 1)
        #expect(restoredHeaders.contains { $0.id == parent.id && $0.messageID == parent.messageID })
        let restoredSent = try #require(restoredHeaders.first { $0.id == sent.id })
        #expect(restoredSent == sent)
        #expect(try await restored.body(for: sent.id, sourceID: Self.sourceA) == sentBody)
        await restored.extensionService(ScheduledSendManaging.self)?.deliverDueScheduledSends()
        let (afterRetry, _) = try await restored.messages(in: parentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(afterRetry.filter { $0.messageID == expectedMessageID }.count == 1)
    }

    @Test("immediate sends persist exact Sent records and remain idempotent")
    func immediateSendPersistsDeliveredRecord() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, now: { Self.now })
        let draft = Draft(
            id: "immediate-persisted",
            to: [Correspondent(email: "recipient@example.test")],
            subject: "Immediate",
            htmlBody: "<p>Immediate body</p>"
        )

        let first = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let repeated = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let sentID = try #require(first.sentMessageID)
        #expect(repeated.sentMessageID == sentID)
        let sentFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        let sent = try #require(headers.first { $0.id == sentID })
        #expect(headers.filter { $0.id == sentID }.count == 1)
        #expect(sent.date == Self.now)
        #expect(sent.messageID == MIMEMessageBuilder.messageIDHeaderValue(
            draftID: draft.id,
            fromEmail: "primary@example.test"
        ))
        let body = try await backend.body(for: sentID, sourceID: Self.sourceA)

        let restored = Self.backend(persistenceDirectory: directory, now: { Self.now.addingTimeInterval(50000) })
        let (restoredHeaders, _) = try await restored.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(restoredHeaders == [sent])
        #expect(try await restored.body(for: sentID, sourceID: Self.sourceA) == body)
    }

    @Test("due processing waits until the exact scheduled boundary")
    func dueBoundaryIsInclusive() async throws {
        let clock = MockScheduledSendClock(Self.now)
        let backend = Self.backend(persistenceDirectory: nil, now: { clock.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let scheduledFor = Self.now.addingTimeInterval(60)
        _ = try await backend.send(
            draft: Draft(id: "due-boundary", scheduledFor: scheduledFor),
            sourceID: Self.sourceA
        )

        await scheduler.deliverDueScheduledSends()
        #expect(scheduler.pendingScheduledSends().count == 1)
        clock.advance(to: scheduledFor)
        await scheduler.deliverDueScheduledSends()
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let sentFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.filter { $0.date == scheduledFor }.count == 1)
    }

    @Test("journal refresh preserves live Sent mutations")
    func journalRefreshPreservesSentMutations() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, now: { Self.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let archiveFolder = try await backend.createFolder(name: "Archive", parentID: nil, sourceID: Self.sourceA)
        for id in ["flagged-sent", "moved-sent", "deleted-sent"] {
            _ = try await backend.send(
                draft: Draft(id: id, subject: id, scheduledFor: Self.now),
                sourceID: Self.sourceA
            )
        }
        await scheduler.deliverDueScheduledSends()

        let folders = try await backend.folders(in: Self.sourceA)
        let sentFolder = try #require(folders.first { $0.role == .sent })
        let (sentBefore, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        let flagged = try #require(sentBefore.first { $0.subject == "flagged-sent" })
        let moved = try #require(sentBefore.first { $0.subject == "moved-sent" })
        let deleted = try #require(sentBefore.first { $0.subject == "deleted-sent" })
        try await backend.setFlagged(true, for: [flagged.id], sourceID: Self.sourceA)
        try await backend.move(messageIDs: [moved.id], to: archiveFolder, sourceID: Self.sourceA)
        try await backend.delete(messageIDs: [deleted.id], sourceID: Self.sourceA)

        _ = try await backend.send(
            draft: Draft(id: "unrelated-queued", scheduledFor: Self.now.addingTimeInterval(3600)),
            sourceID: Self.sourceA
        )
        await scheduler.deliverDueScheduledSends()

        let (sentAfter, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(sentAfter.map(\.id) == [flagged.id])
        #expect(sentAfter.first?.isFlagged == true)
        let (archived, _) = try await backend.messages(in: archiveFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(archived.contains { $0.id == moved.id })
        let trashFolder = try #require(try await backend.folders(in: Self.sourceA).first { $0.role == .trash })
        let (trashed, _) = try await backend.messages(in: trashFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(trashed.contains { $0.id == deleted.id })
        #expect(scheduler.pendingScheduledSends().map(\.draftID) == ["unrelated-queued"])
    }

    @Test("queued and canceled Draft projection dates remain stable across restart")
    func draftProjectionDatePersistsAcrossRestart() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, now: { Self.now })
        _ = try await backend.send(
            draft: Draft(id: "projection-date", scheduledFor: Self.now.addingTimeInterval(60)),
            sourceID: Self.sourceA
        )
        let draftsFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .drafts })
        let (queuedHeaders, _) = try await backend.messages(in: draftsFolder, sourceID: Self.sourceA, pageToken: nil)
        let queued = try #require(queuedHeaders.first { $0.id == "draft-projection-date" })
        #expect(queued.date == Self.now)

        let reopened = Self.backend(persistenceDirectory: directory, now: { Self.now.addingTimeInterval(50000) })
        let editor = try #require(reopened.extensionService(ScheduledSendEditing.self))
        let reopenedDrafts = try #require(await reopened.folders(in: Self.sourceA).first { $0.role == .drafts })
        let (restoredQueuedHeaders, _) = try await reopened.messages(
            in: reopenedDrafts,
            sourceID: Self.sourceA,
            pageToken: nil
        )
        let restoredQueued = try #require(restoredQueuedHeaders.first { $0.id == queued.id })
        #expect(restoredQueued.date == Self.now)
        let scheduleID = try #require(editor.pendingScheduledSends().first?.id)
        _ = try await editor.cancelScheduledSend(id: scheduleID)
        let (canceledHeaders, _) = try await reopened.messages(in: reopenedDrafts, sourceID: Self.sourceA, pageToken: nil)
        let canceled = try #require(canceledHeaders.first { $0.id == queued.id })
        #expect(canceled.date == Self.now.addingTimeInterval(50000))

        var editedCanceledDraft = try #require(try await reopened.draft(for: "projection-date", sourceID: Self.sourceA))
        editedCanceledDraft.htmlBody = "<p>saved after cancel</p>"
        _ = try await reopened.save(draft: editedCanceledDraft, sourceID: Self.sourceA)
        let (savedCanceledHeaders, _) = try await reopened.messages(
            in: reopenedDrafts,
            sourceID: Self.sourceA,
            pageToken: nil
        )
        let savedCanceled = try #require(savedCanceledHeaders.first { $0.id == queued.id })
        #expect(savedCanceled.date == canceled.date)

        try await reopened.setFlagged(true, for: [canceled.id], sourceID: Self.sourceA)
        _ = try await reopened.send(
            draft: Draft(id: "unrelated-after-cancel", scheduledFor: Self.now.addingTimeInterval(60000)),
            sourceID: Self.sourceA
        )
        await reopened.extensionService(ScheduledSendManaging.self)?.deliverDueScheduledSends()
        let (mutatedCanceledHeaders, _) = try await reopened.messages(
            in: reopenedDrafts,
            sourceID: Self.sourceA,
            pageToken: nil
        )
        #expect(mutatedCanceledHeaders.first { $0.id == canceled.id }?.isFlagged == true)
        #expect(mutatedCanceledHeaders.first { $0.id == canceled.id }?.date == canceled.date)

        let reopenedAgain = Self.backend(persistenceDirectory: directory, now: { Self.now.addingTimeInterval(100_000) })
        let finalDrafts = try #require(await reopenedAgain.folders(in: Self.sourceA).first { $0.role == .drafts })
        let (restoredCanceledHeaders, _) = try await reopenedAgain.messages(
            in: finalDrafts,
            sourceID: Self.sourceA,
            pageToken: nil
        )
        #expect(try #require(restoredCanceledHeaders.first { $0.id == queued.id }).date == savedCanceled.date)
    }

    @Test("persistent writes fail closed before accepting a schedule")
    func failedPersistentWriteDoesNotAcceptSchedule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        var draft = Draft(id: "no-write", scheduledFor: Self.now)
        draft.subject = "must not be accepted"

        await #expect(throws: (any Error).self) { try await backend.send(draft: draft, sourceID: Self.sourceA) }
        #expect(scheduler.pendingScheduledSends().isEmpty)
        #expect(try Data(contentsOf: directory) == Data([1]))
    }

    @Test("a purged Mock cannot reconnect or mutate the next login journal")
    func purgedStoreCannotAffectFreshLoginJournal() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldBackend = Self.backend(persistenceDirectory: directory)
        _ = try await oldBackend.send(
            draft: Draft(id: "old-login", scheduledFor: Self.now.addingTimeInterval(3600)),
            sourceID: Self.sourceA
        )
        try await oldBackend.purgePersistentState()

        let freshBackend = Self.backend(persistenceDirectory: directory)
        _ = try await freshBackend.send(
            draft: Draft(id: "fresh-login", scheduledFor: Self.now.addingTimeInterval(3600)),
            sourceID: Self.sourceA
        )
        let freshScheduler = try #require(freshBackend.extensionService(ScheduledSendManaging.self))
        let freshScheduleID = try #require(freshScheduler.pendingScheduledSends().first?.id)

        await #expect(throws: (any Error).self) { try await oldBackend.connect() }
        await #expect(throws: (any Error).self) {
            try await oldBackend.send(
                draft: Draft(id: "stale-send", scheduledFor: Self.now.addingTimeInterval(7200)),
                sourceID: Self.sourceA
            )
        }
        await #expect(throws: (any Error).self) {
            try await oldBackend.save(draft: Draft(id: "stale-save"), sourceID: Self.sourceA)
        }
        try await oldBackend.purgePersistentState()

        let restored = Self.backend(persistenceDirectory: directory)
        let restoredScheduler = try #require(restored.extensionService(ScheduledSendManaging.self))
        #expect(restoredScheduler.pendingScheduledSends().map(\.id) == [freshScheduleID])
    }

    @Test("corrupt journal storage is not overwritten")
    func corruptJournalFailsClosed() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: journal.fileURL)
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let draft = Draft(id: "corrupt", scheduledFor: Self.now)

        await #expect(throws: (any Error).self) { try await backend.send(draft: draft, sourceID: Self.sourceA) }
        #expect(scheduler.pendingScheduledSends().isEmpty)
        #expect(try Data(contentsOf: journal.fileURL) == corruptBytes)
    }

    @Test("invalid queued identity retains the last known good queue and fails connect")
    func invalidQueuedIdentityFailsClosed() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        _ = try await backend.send(
            draft: Draft(id: "invalid-queue", scheduledFor: Self.now),
            sourceID: Self.sourceA
        )
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        var file = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: journal.fileURL)) as? [String: Any]
        )
        var records = try #require(file["records"] as? [[String: Any]])
        records[0]["scheduleID"] = records[0]["draftID"]
        file["records"] = records
        let invalidData = try JSONSerialization.data(withJSONObject: file, options: [.sortedKeys])
        try invalidData.write(to: journal.fileURL, options: .atomic)

        await #expect(throws: (any Error).self) { try await backend.connect() }
        #expect(scheduler.pendingScheduledSends().map(\.draftID) == ["invalid-queue"])
    }

    @Test("missing established journal directory retains the last good queue and recovers")
    func missingEstablishedJournalDirectoryFailsClosed() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory, now: { Self.now })
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        _ = try await backend.send(
            draft: Draft(id: "missing-directory", scheduledFor: Self.now.addingTimeInterval(3600)),
            sourceID: Self.sourceA
        )
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        let acceptedJournal = try Data(contentsOf: journal.fileURL)
        try FileManager.default.removeItem(at: directory)

        await scheduler.deliverDueScheduledSends()

        #expect(scheduler.pendingScheduledSends().map(\.draftID) == ["missing-directory"])
        await #expect(throws: (any Error).self) { try await backend.connect() }
        await #expect(throws: (any Error).self) { try await backend.folders(in: Self.sourceA) }
        #expect(scheduler.pendingScheduledSends().map(\.draftID) == ["missing-directory"])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try acceptedJournal.write(to: journal.fileURL, options: .atomic)
        try await backend.connect()
        #expect(scheduler.pendingScheduledSends().map(\.draftID) == ["missing-directory"])
    }

    @Test("corrupt initial journals fail through source folder and message loading")
    func corruptInitialJournalFailsSourceLoading() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: journal.fileURL)
        let backend = Self.backend(persistenceDirectory: directory)
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        await #expect(throws: ScheduledSendEditingError.self) { try await backend.folders(in: Self.sourceA) }
        await #expect(throws: ScheduledSendEditingError.self) {
            try await backend.messages(in: inbox, sourceID: Self.sourceA, pageToken: nil)
        }
    }

    @Test("failed first journal write does not establish a marker and purge resets owner state")
    func failedFirstJournalWriteAndPurgeRecovery() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        #expect(try journal.load().isEmpty)
        let nonDirectoryParent = directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: nonDirectoryParent)
        let invalidParentJournal = MockSendJournal(
            directoryURL: nonDirectoryParent.appendingPathComponent("journal", isDirectory: true),
            accountID: Self.account.id
        )
        #expect(throws: (any Error).self) { try invalidParentJournal.load() }
        let draft = Draft(id: "first-write", scheduledFor: Self.now)
        let record = MockSendJournalRecord(
            recordID: "first-record",
            accountID: Self.account.id,
            sourceID: Self.sourceA,
            draftID: draft.id,
            scheduleID: "opaque-first-write",
            draft: draft,
            attachments: [],
            state: .queued,
            scheduledFor: Self.now,
            sentHeader: nil,
            sentBody: nil,
            nextAttemptAt: nil,
            sender: Correspondent(email: "primary@example.test"),
            parentMessageID: nil,
            references: nil,
            draftProjectionDate: Self.now
        )
        #expect(throws: (any Error).self) {
            try journal.transact { records in
                try FileManager.default.createDirectory(at: journal.fileURL, withIntermediateDirectories: false)
                records.append(record)
            }
        }
        try FileManager.default.removeItem(at: journal.fileURL)
        #expect(try journal.load().isEmpty)
        _ = try journal.transact { $0.append(record) }
        #expect(try journal.load() == [record])

        try FileManager.default.removeItem(at: directory)
        #expect(throws: (any Error).self) { try journal.load() }
        try journal.purge()
        #expect(try journal.load().isEmpty)
        _ = try journal.transact { $0.append(record) }
        #expect(try journal.load() == [record])
    }

    @Test("one source and draft identity reuses the exact delivered receipt")
    func deliveredDraftIdentityIsImmutable() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let draft = Draft(id: "one-send", subject: "Original", htmlBody: "Original body")
        let first = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let sentID = try #require(first.sentMessageID)
        var laterSubmission = draft
        laterSubmission.subject = "Changed after delivery"
        laterSubmission.htmlBody = "Changed body"
        laterSubmission.scheduledFor = Self.now.addingTimeInterval(60)

        let repeated = try await backend.send(draft: laterSubmission, sourceID: Self.sourceA)
        _ = try await backend.save(draft: laterSubmission, sourceID: Self.sourceA)

        #expect(repeated.sentMessageID == sentID)
        #expect(repeated.scheduledFor == nil)
        #expect(backend.extensionService(ScheduledSendManaging.self)?.pendingScheduledSends().isEmpty == true)
        #expect(try await backend.draft(for: draft.id, sourceID: Self.sourceA) == nil)
        let sentFolder = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await backend.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.count == 1)
        #expect(headers[0].id == sentID)
        #expect(headers[0].subject == "Original")
        #expect(try await backend.body(for: sentID, sourceID: Self.sourceA).html == "Original body")
        #expect(try MockSendJournal(directoryURL: directory, accountID: Self.account.id).load().count == 1)
    }

    @Test("concurrent immediate sends from separate Mock instances commit one receipt")
    func concurrentImmediateSendsShareTransactionIdentity() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstBackend = Self.backend(persistenceDirectory: directory)
        let secondBackend = Self.backend(persistenceDirectory: directory)
        let draft = Draft(id: "concurrent-immediate", subject: "One receipt")

        async let first = firstBackend.send(draft: draft, sourceID: Self.sourceA)
        async let second = secondBackend.send(draft: draft, sourceID: Self.sourceA)
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult.sentMessageID == secondResult.sentMessageID)
        #expect(try MockSendJournal(directoryURL: directory, accountID: Self.account.id).load().count == 1)
    }

    @Test("cancel and resubmit replace one source-scoped journal record")
    func cancelAndResubmitReplaceJournalIdentity() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let editor = try #require(backend.extensionService(ScheduledSendEditing.self))
        var draft = Draft(id: "cancel-resubmit", scheduledFor: Self.now.addingTimeInterval(60))
        _ = try await backend.send(draft: draft, sourceID: Self.sourceA)
        let originalID = try #require(editor.pendingScheduledSends().first?.id)
        _ = try await editor.cancelScheduledSend(id: originalID)
        draft.scheduledFor = Self.now.addingTimeInterval(120)

        _ = try await backend.send(draft: draft, sourceID: Self.sourceA)

        let replacementID = try #require(editor.pendingScheduledSends().first?.id)
        #expect(replacementID != originalID)
        let records = try MockSendJournal(directoryURL: directory, accountID: Self.account.id).load()
        #expect(records.count == 1)
        #expect(records[0].scheduleID == replacementID)
    }

    @Test("a pre-existing Mock refreshes canceled payloads and delivered attachments and reply context")
    func crossInstanceRefreshProjectsFrozenPayload() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = MessageHeader(
            id: "seed-parent",
            threadID: "seed-thread",
            folderID: "inbox",
            from: Correspondent(email: "parent@example.test"),
            subject: "Parent",
            snippet: "",
            date: Self.now,
            messageID: "parent@example.test",
            references: ["root@example.test", "parent@example.test"]
        )
        let original = Self.backend(persistenceDirectory: directory, messagesByFolder: ["inbox": [parent]])
        let second = Self.backend(persistenceDirectory: directory, sourceAMailboxEmail: "changed@example.test")
        let cancelAttachmentID = try await original.uploadAttachment(
            draftID: "cross-cancel",
            data: Data([4, 5]),
            filename: "cancel.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let canceledDraft = Draft(
            id: "cross-cancel",
            attachmentIDs: [cancelAttachmentID],
            scheduledFor: Self.now.addingTimeInterval(60)
        )
        _ = try await original.send(draft: canceledDraft, sourceID: Self.sourceA)
        let originalEditor = try #require(original.extensionService(ScheduledSendEditing.self))
        let canceledID = try #require(originalEditor.pendingScheduledSends().first?.id)
        await second.deliverDueScheduledSends()
        _ = try await originalEditor.cancelScheduledSend(id: canceledID)

        await second.deliverDueScheduledSends()

        let refreshedDraft = try #require(try await second.draft(for: canceledDraft.id, sourceID: Self.sourceA))
        #expect(refreshedDraft.scheduledFor == nil)
        #expect(try await second.localDraftAttachments(for: refreshedDraft, sourceID: Self.sourceA).map(\.data) == [Data([4, 5])])

        let sentAttachmentID = try await original.uploadAttachment(
            draftID: "cross-reply",
            data: Data([6, 7, 8]),
            filename: "reply.bin",
            mimeType: "application/octet-stream",
            sourceID: Self.sourceA
        )
        let reply = Draft(
            id: "cross-reply",
            inReplyToMessageID: parent.id,
            to: [Correspondent(email: "recipient@example.test")],
            subject: "Reply",
            htmlBody: "Frozen reply",
            attachmentIDs: [sentAttachmentID],
            scheduledFor: Self.now
        )
        _ = try await original.send(draft: reply, sourceID: Self.sourceA)
        await second.deliverDueScheduledSends()

        let sentFolder = try #require(await second.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await second.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        let sent = try #require(headers.first { $0.subject == "Reply" })
        #expect(sent.from.email == "primary@example.test")
        #expect(sent.messageID == MIMEMessageBuilder.messageIDHeaderValue(
            draftID: reply.id,
            fromEmail: "primary@example.test"
        ))
        #expect(sent.inReplyTo == "parent@example.test")
        #expect(sent.references == ["root@example.test", "parent@example.test"])
        let body = try await second.body(for: sent.id, sourceID: Self.sourceA)
        #expect(try await second.downloadAttachment(#require(body.attachments.first), sourceID: Self.sourceA) == Data([6, 7, 8]))
    }

    @Test("an unavailable source stays queued for another instance that owns it")
    func unavailableSourceDoesNotConsumeQueue() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = Self.backend(persistenceDirectory: directory)
        _ = try await owner.send(
            draft: Draft(id: "unavailable-source", scheduledFor: Self.now),
            sourceID: Self.sourceB
        )
        let unknownSource = Self.backend(
            persistenceDirectory: directory,
            mailboxes: [Mailbox(id: "mailbox-a", email: "primary@example.test", displayName: "A", isPrimary: true)]
        )

        await unknownSource.deliverDueScheduledSends()

        #expect(unknownSource.pendingScheduledSends().map(\.sourceID) == [Self.sourceB])
        await owner.deliverDueScheduledSends()
        #expect(owner.pendingScheduledSends().isEmpty)
    }

    @Test("failed discard retains scheduled state and reports the storage failure")
    func failedDiscardDoesNotCancelSchedule() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        let draft = try await backend.save(draft: Draft(id: "discard-failure"), sourceID: Self.sourceA)
        _ = try await backend.send(
            draft: Draft(id: draft.id, scheduledFor: Self.now.addingTimeInterval(60)),
            sourceID: Self.sourceA
        )
        let journal = MockSendJournal(directoryURL: directory, accountID: Self.account.id)
        try FileManager.default.removeItem(at: directory)
        try Data([0x7F]).write(to: directory)

        await #expect(throws: (any Error).self) { try await backend.discard(draftID: draft.id) }
        await #expect(throws: (any Error).self) { try await backend.discard(draftID: draft.id, sourceID: Self.sourceA) }
        #expect(scheduler.pendingScheduledSends().map(\.draftID) == [draft.id])
        #expect(FileManager.default.fileExists(atPath: journal.fileURL.path) == false)
    }

    @Test("restored overdue work starts the automatic worker")
    func restoredQueueStartsWorker() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Self.backend(persistenceDirectory: directory)
        let draft = Draft(id: "restored-worker", subject: "Restored", scheduledFor: Self.now)
        _ = try await original.send(draft: draft, sourceID: Self.sourceA)

        let restored = Self.backend(
            persistenceDirectory: directory,
            now: { Self.now },
            automaticDeliveryEnabled: true
        )
        let scheduler = try #require(restored.extensionService(ScheduledSendManaging.self))
        for _ in 0 ..< 200 {
            if scheduler.pendingScheduledSends().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let sentFolder = try #require(await restored.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await restored.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.contains { $0.subject == "Restored" })
    }

    @Test("scheduled worker releases its backend and Store while sleeping")
    func scheduledWorkerReleasesOwnerWhileSleeping() async throws {
        let readCounter = MockScheduledSendReadCounter()
        let probe = MockScheduledSendWorkerLifetimeProbe()
        var readsWhileSleeping = 0
        do {
            let clock = MockScheduledSendClock(Self.now, readCounter: readCounter)
            probe.clock = clock
            let backend = Self.backend(
                persistenceDirectory: nil,
                now: { clock.now },
                automaticDeliveryEnabled: true
            )
            probe.backend = backend
            let readsBeforeSchedule = readCounter.readCount
            _ = try await backend.send(
                draft: Draft(id: "worker-release", scheduledFor: Self.now.addingTimeInterval(2)),
                sourceID: Self.sourceA
            )
            for _ in 0 ..< 200 {
                if readCounter.readCount >= readsBeforeSchedule + 3 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(10))
            readsWhileSleeping = readCounter.readCount
            #expect(readsWhileSleeping >= readsBeforeSchedule + 3)
        }
        for _ in 0 ..< 100 {
            if probe.backend == nil, probe.clock == nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(probe.backend == nil)
        #expect(probe.clock == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(readCounter.readCount == readsWhileSleeping)
    }

    @Test("disconnect pauses overdue work until reconnect")
    func disconnectPausesUntilReconnect() async throws {
        let backend = Self.backend(persistenceDirectory: nil)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))
        _ = try await backend.send(
            draft: Draft(id: "reconnect", scheduledFor: Self.now),
            sourceID: Self.sourceA
        )

        await backend.disconnect()
        await scheduler.deliverDueScheduledSends()
        #expect(scheduler.pendingScheduledSends().count == 1)
        try await backend.connect()
        #expect(scheduler.pendingScheduledSends().isEmpty)
    }

    @Test("concurrent reconnects deliver one local receipt")
    func concurrentReconnectsDeliverOnce() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Self.backend(persistenceDirectory: directory)
        _ = try await original.send(
            draft: Draft(
                id: "worker-race",
                subject: "Worker race",
                scheduledFor: Self.now.addingTimeInterval(60)
            ),
            sourceID: Self.sourceA
        )
        let originalScheduler = try #require(original.extensionService(ScheduledSendManaging.self))
        let scheduleID = try #require(originalScheduler.pendingScheduledSends().first?.id)
        let restored = Self.backend(
            persistenceDirectory: directory,
            now: { Self.now },
            automaticDeliveryEnabled: true
        )
        let editor = try #require(restored.extensionService(ScheduledSendEditing.self))
        try await editor.rescheduleSend(id: scheduleID, for: Self.now)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask { try await restored.connect() }
            }
            try await group.waitForAll()
        }
        let scheduler = try #require(restored.extensionService(ScheduledSendManaging.self))
        for _ in 0 ..< 500 {
            if scheduler.pendingScheduledSends().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(scheduler.pendingScheduledSends().isEmpty)
        let sentFolder = try #require(await restored.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await restored.messages(in: sentFolder, sourceID: Self.sourceA, pageToken: nil)
        #expect(headers.filter { $0.subject == "Worker race" }.count == 1)
    }

    private static func backend(
        persistenceDirectory: URL?,
        now: @escaping @Sendable () -> Date = { Self.now },
        automaticDeliveryEnabled: Bool = false,
        messagesByFolder: [String: [MessageHeader]] = [:],
        sourceAMailboxEmail: String = "primary@example.test",
        mailboxes: [Mailbox]? = nil
    ) -> MockBackend {
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "drafts", name: "Drafts", role: .drafts),
            Folder(id: "sent", name: "Sent", role: .sent)
        ]
        return MockBackend(
            account: Self.account,
            folders: folders,
            messagesByFolder: messagesByFolder,
            mailboxes: mailboxes ?? [
                Mailbox(id: "mailbox-a", email: sourceAMailboxEmail, displayName: "A", isPrimary: true),
                Mailbox(id: "mailbox-b", email: "secondary@example.test", displayName: "B")
            ],
            supportsScheduledSend: true,
            persistenceDirectory: persistenceDirectory,
            now: now,
            automaticDeliveryEnabled: automaticDeliveryEnabled
        )
    }

    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockScheduledSendTests-\(UUID().uuidString)", isDirectory: true)
        return directory
    }
}

private final class MockScheduledSendClock: @unchecked Sendable {
    private let lock = NSLock()
    private let readCounter: MockScheduledSendReadCounter
    private var value: Date

    init(_ value: Date, readCounter: MockScheduledSendReadCounter = MockScheduledSendReadCounter()) {
        self.value = value
        self.readCounter = readCounter
    }

    var now: Date {
        readCounter.recordRead()
        return lock.withLock { value }
    }

    func advance(to value: Date) {
        lock.withLock { self.value = value }
    }
}

private final class MockScheduledSendReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func recordRead() {
        lock.withLock { count += 1 }
    }
}

private final class MockScheduledSendWorkerLifetimeProbe {
    weak var backend: MockBackend?
    weak var clock: MockScheduledSendClock?
}
