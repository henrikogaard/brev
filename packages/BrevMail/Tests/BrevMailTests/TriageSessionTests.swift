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
@testable import BrevMail
import Foundation
import Testing

@Suite("Triage mode")
@MainActor
struct TriageSessionTests {
    private static let source = MailSourceID(accountID: "acct-1", mailboxID: "box-1")
    private static let otherSource = MailSourceID(accountID: "acct-2", mailboxID: "box-2")

    private static func header(
        id: String,
        threadID: String? = nil,
        folderID: String = "inbox",
        sender: String = "maya@example.com",
        subject: String = "Subject",
        minutesAgo: Double = 0,
        now: Date = Date(timeIntervalSince1970: 1_794_500_000)
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID ?? id,
            folderID: folderID,
            from: Correspondent(name: "Maya", email: sender),
            subject: subject,
            snippet: "Snippet for \(id)",
            date: now.addingTimeInterval(-minutesAgo * 60),
            isRead: false
        )
    }

    @Test("Queue builder collapses messages into one item per conversation and skips snoozed or done rows")
    func queueBuilderGroupsConversationsAndExcludesSnoozed() {
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        let newestInThread = Self.header(id: "m2", threadID: "t1", subject: "Roadmap", minutesAgo: 5, now: now)
        let olderInThread = Self.header(id: "m1", threadID: "t1", subject: "Roadmap", minutesAgo: 60, now: now)
        let snoozed = Self.header(id: "m3", threadID: "t2", subject: "Snoozed", minutesAgo: 10, now: now)
        let secondConversation = Self.header(id: "m4", threadID: "t3", subject: "Dinner", minutesAgo: 20, now: now)

        var workflow = LocalMessageWorkflowState()
        workflow = LocalMessageWorkflowStatePolicy.snoozing(
            SourceMessageID(sourceID: Self.source, messageID: snoozed.id),
            until: now.addingTimeInterval(3600),
            in: workflow
        )

        let items = TriageQueueBuilder.build(
            entries: [
                (Self.source, newestInThread),
                (Self.source, olderInThread),
                (Self.source, snoozed),
                (Self.source, secondConversation),
            ],
            workflowState: workflow,
            now: now
        )

        #expect(items.count == 2)
        #expect(items[0].header.id == "m2")
        #expect(items[0].threadHeaders.map(\.id) == ["m1", "m2"])
        #expect(items[1].header.id == "m4")
        #expect(items[1].threadHeaders.map(\.id) == ["m4"])
    }

    @Test("Skip advances to the next conversation and Undo restores the skipped item")
    func skipAndUndo() async {
        let h1 = Self.header(id: "m1", subject: "First")
        let h2 = Self.header(id: "m2", subject: "Second")
        let undoQueue = UndoQueue(timeout: 30)
        let session = TriageSession(
            items: [
                TriageItem(sourceID: Self.source, header: h1, threadHeaders: [h1]),
                TriageItem(sourceID: Self.source, header: h2, threadHeaders: [h2]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: Self.source,
                selectedFolderID: "inbox",
                selectedMessageID: "m1",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        #expect(session.remainingCount == 2)
        #expect(session.currentItem?.header.id == "m1")
        #expect(session.nextItem?.header.id == "m2")

        session.skipCurrent(registeringUndoIn: undoQueue)
        #expect(session.remainingCount == 1)
        #expect(session.currentItem?.header.id == "m2")
        #expect(session.progress == 0.5)
        #expect(undoQueue.canUndo)

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        #expect(session.remainingCount == 2)
        #expect(session.currentItem?.header.id == "m1")
    }

    @Test("Archive removes the current conversation and Undo restores both backend and session position")
    func archiveAndUndo() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let initialHeaders = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(initialHeaders.count >= 2)

        let first = initialHeaders[0]
        let second = initialHeaders[1]
        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let undoQueue = UndoQueue(timeout: 30)

        let session = TriageSession(
            items: [
                TriageItem(sourceID: sourceID, header: first, threadHeaders: [first]),
                TriageItem(sourceID: sourceID, header: second, threadHeaders: [second]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: sourceID,
                selectedFolderID: inbox.id,
                selectedMessageID: first.id,
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let archived = await session.archiveCurrent(
            undoQueue: undoQueue,
            performArchive: { item in
                let receipt = try await backend.moveWithUndo(
                    messageIDs: [item.header.id],
                    from: inbox,
                    to: archive,
                    sourceID: item.sourceID
                )
                guard let receipt else { return nil }
                return {
                    try await receipt.restore()
                }
            }
        )

        #expect(archived)
        #expect(session.currentItem?.header.id == second.id)
        #expect(session.remainingCount == 1)

        let inboxAfterArchive = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(!inboxAfterArchive.contains { $0.id == first.id })

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        #expect(session.currentItem?.header.id == first.id)
        #expect(session.remainingCount == 2)

        let inboxAfterUndo = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(inboxAfterUndo.contains { $0.id == first.id })
    }

    @Test("Snooze until tomorrow records tomorrow 09:00 and Undo restores the conversation")
    func snoozeUntilTomorrowAndUndo() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 15, minute: 30))!
        let expectedWake = SnoozeQuickOption.tomorrowMorning.wakeDate(now: now, calendar: calendar)!

        let h1 = Self.header(id: "m1", subject: "Follow up", now: now)
        let h2 = Self.header(id: "m2", subject: "Next", now: now)
        let undoQueue = UndoQueue(timeout: 30)
        var workflow = LocalMessageWorkflowState()

        let session = TriageSession(
            items: [
                TriageItem(sourceID: Self.source, header: h1, threadHeaders: [h1]),
                TriageItem(sourceID: Self.source, header: h2, threadHeaders: [h2]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: Self.source,
                selectedFolderID: "inbox",
                selectedMessageID: "m1",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let snoozed = session.snoozeCurrentUntilTomorrow(
            now: now,
            calendar: calendar,
            undoQueue: undoQueue,
            applySnooze: { item, wakeDate in
                let previous = workflow
                workflow = LocalMessageWorkflowStatePolicy.snoozing(
                    SourceMessageID(sourceID: item.sourceID, messageID: item.header.id),
                    until: wakeDate,
                    in: previous
                )
                return { workflow = previous }
            }
        )

        #expect(snoozed)
        #expect(session.currentItem?.header.id == "m2")
        #expect(LocalMessageWorkflowLookup(state: workflow).activeSnooze(
            for: SourceMessageID(sourceID: Self.source, messageID: "m1"),
            at: now
        )?.wakeAt == expectedWake)

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        #expect(session.currentItem?.header.id == "m1")
        #expect(LocalMessageWorkflowLookup(state: workflow).activeSnooze(
            for: SourceMessageID(sourceID: Self.source, messageID: "m1"),
            at: now
        ) == nil)
    }

    @Test("Preloading warms the next conversation body ahead of advancing")
    func preloadsNextConversationBody() async {
        let h1 = Self.header(id: "m1", subject: "One")
        let h2 = Self.header(id: "m2", subject: "Two")
        let session = TriageSession(
            items: [
                TriageItem(sourceID: Self.source, header: h1, threadHeaders: [h1]),
                TriageItem(sourceID: Self.source, header: h2, threadHeaders: [h2]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: Self.source,
                selectedFolderID: "inbox",
                selectedMessageID: "m1",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let loadedBody = MessageBody(messageID: "m2", plainText: "Preloaded body")
        await session.preloadNextNow { item in
            #expect(item.header.id == "m2")
            return loadedBody
        }

        let id2 = SourceMessageID(sourceID: Self.source, messageID: "m2")
        #expect(session.preloadedBody(for: id2)?.plainText == "Preloaded body")
    }

    @Test("Keyboard policy maps E/H/R/J/Esc, respects snooze capability, and ignores text input or command modifiers")
    func keyboardPolicy() {
        #expect(TriageKeyboardPolicy.action(for: "e", hasModifier: false, isEditingText: false, canSnooze: true) == .archive)
        #expect(TriageKeyboardPolicy.action(for: "E", hasModifier: false, isEditingText: false, canSnooze: true) == .archive)
        #expect(TriageKeyboardPolicy.action(for: "h", hasModifier: false, isEditingText: false, canSnooze: true) == .snooze)
        #expect(TriageKeyboardPolicy.action(for: "h", hasModifier: false, isEditingText: false, canSnooze: false) == nil)
        #expect(TriageKeyboardPolicy.action(for: "r", hasModifier: false, isEditingText: false, canSnooze: true) == .reply)
        #expect(TriageKeyboardPolicy.action(for: "j", hasModifier: false, isEditingText: false, canSnooze: true) == .skip)
        #expect(TriageKeyboardPolicy.action(for: "\u{1B}", hasModifier: false, isEditingText: false, canSnooze: true) == .done)

        // Never fire single keys while typing or when Command/Option/Control is held.
        #expect(TriageKeyboardPolicy.action(for: "e", hasModifier: false, isEditingText: true, canSnooze: true) == nil)
        #expect(TriageKeyboardPolicy.action(for: "j", hasModifier: true, isEditingText: false, canSnooze: true) == nil)
    }

    @Test("End-to-end triage UI flow covers start, archive, skip, undo, and exit back to the original list position")
    func endToEndStartArchiveSkipUndoExitFlow() async throws {
        let backend = MockBackend()
        let folders = try await backend.folders()
        let inbox = try #require(folders.first { $0.role == .inbox })
        let archive = try #require(folders.first { $0.role == .archive })
        let headers = try await backend.messages(in: inbox, pageToken: nil).headers
        #expect(headers.count >= 3)

        let sourceID = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let navigation = MailNavigationState()
        navigation.selectFolder(inbox.id, in: sourceID)
        navigation.replaceCurrentFolderHeaders(headers)
        navigation.selectedMessageID = headers[1].id

        let returnPosition = TriageReturnPosition(
            selectedSourceID: navigation.selectedSourceID,
            selectedFolderID: navigation.selectedFolderID,
            selectedMessageID: navigation.selectedMessageID,
            isUnifiedInboxSelected: navigation.isUnifiedInboxSelected,
            isSmartViewSelected: navigation.isSmartViewSelected
        )

        let items = TriageQueueBuilder.build(
            entries: headers.map { (sourceID, $0) },
            workflowState: LocalMessageWorkflowState()
        )
        let session = TriageSession(items: items, returnPosition: returnPosition)
        let undoQueue = UndoQueue(timeout: 30)

        let firstID = try #require(session.currentItem?.header.id)
        let secondID = try #require(session.nextItem?.header.id)

        // 1. Archive first conversation
        let didArchive = await session.archiveCurrent(undoQueue: undoQueue) { item in
            let receipt = try await backend.moveWithUndo(
                messageIDs: item.threadHeaders.map(\.id),
                from: inbox,
                to: archive,
                sourceID: item.sourceID
            )
            guard let receipt else { return nil }
            return {
                try await receipt.restore()
            }
        }
        #expect(didArchive)
        #expect(session.currentItem?.header.id == secondID)

        // 2. Dedicated reader navigation tracks Triage while main navigation stays intact
        let readerNav = MailNavigationState()
        session.syncReaderNavigation(readerNav)
        #expect(readerNav.selectedMessageID == secondID)
        #expect(readerNav.selectedSourceID == sourceID)
        #expect(navigation.selectedMessageID == headers[1].id)

        // 3. Skip second conversation
        session.skipCurrent(registeringUndoIn: undoQueue)
        #expect(session.currentItem?.header.id != secondID)

        // 4. Undo reverses the skip back to the second conversation
        let didUndoSkip = await undoQueue.undo()?.value ?? false
        #expect(didUndoSkip)
        #expect(session.currentItem?.header.id == secondID)

        // 5. Exit leaves the original mailbox navigation (folder, filter, selection) intact
        session.cancelPreload()
        #expect(navigation.selectedSourceID == sourceID)
        #expect(navigation.selectedFolderID == inbox.id)
        #expect(navigation.selectedMessageID == headers[1].id)
        #expect(firstID != secondID)
    }

    @Test("Archive Undo applies restored IMAP UIDs and drops stale preloaded bodies")
    func archiveUndoRemapsRestoredIMAPIDs() async {
        let h1 = Self.header(id: "INBOX:42", subject: "Original")
        let h2 = Self.header(id: "INBOX:43", subject: "Next")
        let undoQueue = UndoQueue(timeout: 30)
        let session = TriageSession(
            items: [
                TriageItem(sourceID: Self.source, header: h1, threadHeaders: [h1]),
                TriageItem(sourceID: Self.source, header: h2, threadHeaders: [h2]),
            ],
            returnPosition: TriageReturnPosition(
                selectedSourceID: Self.source,
                selectedFolderID: "INBOX",
                selectedMessageID: "INBOX:42",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let archived = await session.archiveCurrent(undoQueue: undoQueue) { _ in
            return { ["INBOX:42": "INBOX:73"] }
        }
        #expect(archived)
        #expect(session.currentItem?.header.id == "INBOX:43")

        let undone = await undoQueue.undo()?.value ?? false
        #expect(undone)
        #expect(session.currentItem?.header.id == "INBOX:73")
        #expect(session.currentItem?.threadHeaders.map(\.id) == ["INBOX:73"])
    }

    @Test("Archive without a provider undo receipt skips registering a broken undo step")
    func archiveWithoutReceiptDoesNotRegisterUndo() async {
        let h1 = Self.header(id: "m1", subject: "One")
        let undoQueue = UndoQueue(timeout: 30)
        let session = TriageSession(
            items: [TriageItem(sourceID: Self.source, header: h1, threadHeaders: [h1])],
            returnPosition: TriageReturnPosition(
                selectedSourceID: Self.source,
                selectedFolderID: "inbox",
                selectedMessageID: "m1",
                isUnifiedInboxSelected: false,
                isSmartViewSelected: false
            )
        )

        let archived = await session.archiveCurrent(undoQueue: undoQueue) { _ in nil }
        #expect(archived)
        #expect(!undoQueue.canUndo)
    }

    @Test("Triage copy has Norwegian localizations")
    func norwegianCopy() throws {
        #expect(TriagePresentation.title(remainingCount: 4, locale: Locale(identifier: "en")) == "Triage, 4 left")
        #expect(TriagePresentation.title(remainingCount: 0, locale: Locale(identifier: "en")) == "Triage")

        let catalog = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let requiredKeys = [
            "Triage",
            "Triage, %lld left",
            "Start Triage",
            "Exit Triage",
            "Snooze until tomorrow",
            "Snoozed until tomorrow",
            "Skipped",
            "All caught up",
            "You reviewed every conversation in this queue.",
            "esc",
        ]
        for key in requiredKeys {
            let entry = try #require(catalog[key] as? [String: Any], "Missing catalog key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let nb = try #require(localizations["nb"] as? [String: Any])
            let unit = try #require(nb["stringUnit"] as? [String: Any])
            let value = try #require(unit["value"] as? String)
            #expect(!value.isEmpty)
        }
    }
}
