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
        let backend = Self.backend(persistenceDirectory: directory)
        let scheduler = try #require(backend.extensionService(ScheduledSendManaging.self))

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
        #expect(firstAttachmentID == secondAttachmentID)

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
        #expect(scheduler.pendingScheduledSends().isEmpty)

        var scheduledFirst = first
        scheduledFirst.scheduledFor = Self.now
        var scheduledSecond = second
        scheduledSecond.scheduledFor = Self.now
        let firstResult = try await backend.send(draft: scheduledFirst, sourceID: Self.sourceA)
        let secondResult = try await backend.send(draft: scheduledSecond, sourceID: Self.sourceB)

        #expect(firstResult.sentMessageID == nil)
        #expect(firstResult.scheduledFor == Self.now)
        #expect(secondResult.sentMessageID == nil)
        let entries = scheduler.pendingScheduledSends()
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)
        #expect(entries.allSatisfy { $0.id != "same-draft" })
        #expect(Set(entries.compactMap(\.sourceID)) == [Self.sourceA, Self.sourceB])
        for entry in entries {
            #expect(try await scheduler.scheduledDraft(id: entry.id).id == "same-draft")
        }

        let firstID = try #require(entries.first { $0.sourceID == Self.sourceA }?.id)
        let secondID = try #require(entries.first { $0.sourceID == Self.sourceB }?.id)
        let editing = try #require(backend.extensionService(ScheduledSendEditing.self))
        await #expect(throws: (any Error).self) {
            try await editing.cancelScheduledSend(id: "unknown-schedule-id")
        }
        _ = try await editing.cancelScheduledSend(id: firstID)
        #expect(scheduler.pendingScheduledSends().map(\.id) == [secondID])
        #expect(try await editing.scheduledDraft(id: secondID).subject == "B")

        let sent = try #require(await backend.folders(in: Self.sourceA).first { $0.role == .sent })
        let (sentHeaders, _) = try await backend.messages(in: sent, pageToken: nil, sourceID: Self.sourceA)
        #expect(sentHeaders.isEmpty)
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
        #expect(first.attachmentIDs == second.attachmentIDs)
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
        let (headers, _) = try await deliveringBackend.messages(in: sent, pageToken: nil, sourceID: Self.sourceA)
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
        let (parentHeaders, _) = try await backend.messages(in: parentFolder, pageToken: nil, sourceID: Self.sourceA)
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
            to: [Correspondent(email: "recipient@example.test")],
            subject: "Reply",
            htmlBody: "<p>Exact reply</p>",
            attachmentIDs: [attachmentID],
            scheduledFor: Self.now,
            inReplyToMessageID: parent.id
        )
        let result = try await backend.send(draft: draft, sourceID: Self.sourceA)
        #expect(result.sentMessageID == nil)
        async let firstDelivery: Void = scheduler.deliverDueScheduledSends()
        async let secondDelivery: Void = scheduler.deliverDueScheduledSends()
        _ = await (firstDelivery, secondDelivery)

        let (sentHeaders, _) = try await backend.messages(in: parentFolder, pageToken: nil, sourceID: Self.sourceA)
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
        let (restoredHeaders, _) = try await restored.messages(in: parentFolder, pageToken: nil, sourceID: Self.sourceA)
        #expect(restoredHeaders.filter { $0.messageID == expectedMessageID }.count == 1)
        #expect(restoredHeaders.contains { $0.id == parent.id && $0.messageID == parent.messageID })
        #expect(try await restored.body(for: sent.id, sourceID: Self.sourceA) == sentBody)
        await restored.extensionService(ScheduledSendManaging.self)?.deliverDueScheduledSends()
        let (afterRetry, _) = try await restored.messages(in: parentFolder, pageToken: nil, sourceID: Self.sourceA)
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
        let (headers, _) = try await backend.messages(in: sentFolder, pageToken: nil, sourceID: Self.sourceA)
        let sent = try #require(headers.first { $0.id == sentID })
        #expect(headers.filter { $0.id == sentID }.count == 1)
        #expect(sent.date == Self.now)
        #expect(sent.messageID == MIMEMessageBuilder.messageIDHeaderValue(
            draftID: draft.id,
            fromEmail: "primary@example.test"
        ))
        let body = try await backend.body(for: sentID, sourceID: Self.sourceA)

        let restored = Self.backend(persistenceDirectory: directory, now: { Self.now.addingTimeInterval(50000) })
        let (restoredHeaders, _) = try await restored.messages(in: sentFolder, pageToken: nil, sourceID: Self.sourceA)
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
        let (headers, _) = try await backend.messages(in: sentFolder, pageToken: nil, sourceID: Self.sourceA)
        #expect(headers.filter { $0.date == scheduledFor }.count == 1)
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
        let (headers, _) = try await restored.messages(in: sentFolder, pageToken: nil, sourceID: Self.sourceA)
        #expect(headers.contains { $0.subject == "Restored" })
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

    @Test("overlapping reconnects retain a current worker after an in-flight send")
    func overlappingReconnectsKeepWorker() async throws {
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
        let gate = MockScheduledSendGate()
        restored.sendHandler = { _, _ in
            await gate.waitForFirstCallIfNeeded()
            return SendResult(sentMessageID: "handler-result")
        }
        let editor = try #require(restored.extensionService(ScheduledSendEditing.self))
        try await editor.rescheduleSend(id: scheduleID, for: Self.now)
        await gate.waitUntilFirstCall()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask { try await restored.connect() }
            }
            try await group.waitForAll()
        }
        await gate.releaseFirstCall()
        let scheduler = try #require(restored.extensionService(ScheduledSendManaging.self))
        for _ in 0 ..< 500 {
            if scheduler.pendingScheduledSends().isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(scheduler.pendingScheduledSends().isEmpty)
        #expect(await gate.callCount() >= 2)
        let sentFolder = try #require(await restored.folders(in: Self.sourceA).first { $0.role == .sent })
        let (headers, _) = try await restored.messages(in: sentFolder, pageToken: nil, sourceID: Self.sourceA)
        #expect(headers.filter { $0.subject == "Worker race" }.count == 1)
    }

    private static func backend(
        persistenceDirectory: URL?,
        now: @escaping @Sendable () -> Date = { Self.now },
        automaticDeliveryEnabled: Bool = false
    ) -> MockBackend {
        let folders = [
            Folder(id: "inbox", name: "Inbox", role: .inbox),
            Folder(id: "drafts", name: "Drafts", role: .drafts),
            Folder(id: "sent", name: "Sent", role: .sent)
        ]
        return MockBackend(
            account: Self.account,
            folders: folders,
            messagesByFolder: [:],
            mailboxes: [
                Mailbox(id: "mailbox-a", email: "primary@example.test", displayName: "A", isPrimary: true),
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
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(to value: Date) {
        lock.withLock { self.value = value }
    }
}

private actor MockScheduledSendGate {
    private var hasStarted = false
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var calls = 0

    func waitUntilFirstCall() async {
        if hasStarted { return }
        await withCheckedContinuation { firstCallContinuation = $0 }
    }

    func waitForFirstCallIfNeeded() async {
        calls += 1
        guard calls == 1 else { return }
        hasStarted = true
        firstCallContinuation?.resume()
        firstCallContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func releaseFirstCall() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func callCount() -> Int {
        calls
    }
}
