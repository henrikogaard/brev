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

@Suite("LocalMessageWorkflowVisibilityPolicy")
struct LocalMessageWorkflowVisibilityPolicyTests {
    private let source = MailSourceID(accountID: "acct-1", mailboxID: "personal")
    private let otherSource = MailSourceID(accountID: "acct-1", mailboxID: "work")

    @Test("active folder lists hide locally snoozed and done messages")
    func activeFolderListsHideLocallySnoozedAndDoneMessages() {
        let now = Date(timeIntervalSince1970: 1000)
        let active = Self.header(id: "active")
        let snoozed = Self.header(id: "snoozed")
        let done = Self.header(id: "done")
        let state = LocalMessageWorkflowStatePolicy.markingDone(
            [SourceMessageID(sourceID: source, messageID: done.id)],
            now: now,
            in: LocalMessageWorkflowStatePolicy.snoozing(
                SourceMessageID(sourceID: source, messageID: snoozed.id),
                until: now.addingTimeInterval(3600),
                now: now,
                in: .defaults
            )
        )

        let visible = LocalMessageWorkflowVisibilityPolicy.headers(
            [active, snoozed, done],
            sourceID: source,
            mode: .active,
            state: state,
            now: now
        )

        #expect(visible.map(\.id) == [active.id])
    }

    @Test("expired snoozes return to active lists")
    func expiredSnoozesReturnToActiveLists() {
        let now = Date(timeIntervalSince1970: 1000)
        let header = Self.header(id: "wake")
        let state = LocalMessageWorkflowStatePolicy.snoozing(
            SourceMessageID(sourceID: source, messageID: header.id),
            until: now,
            now: now.addingTimeInterval(-3600),
            in: .defaults
        )

        let visible = LocalMessageWorkflowVisibilityPolicy.headers(
            [header],
            sourceID: source,
            mode: .active,
            state: state,
            now: now
        )

        #expect(visible.map(\.id) == [header.id])
    }

    @Test("search results keep snoozed and done messages visible")
    func searchResultsKeepSnoozedAndDoneMessagesVisible() {
        let now = Date(timeIntervalSince1970: 2000)
        let snoozed = Self.header(id: "snoozed")
        let done = Self.header(id: "done")
        let state = LocalMessageWorkflowStatePolicy.markingDone(
            [SourceMessageID(sourceID: source, messageID: done.id)],
            now: now,
            in: LocalMessageWorkflowStatePolicy.snoozing(
                SourceMessageID(sourceID: source, messageID: snoozed.id),
                until: now.addingTimeInterval(3600),
                now: now,
                in: .defaults
            )
        )

        let visible = LocalMessageWorkflowVisibilityPolicy.headers(
            [snoozed, done],
            sourceID: source,
            mode: .search,
            state: state,
            now: now
        )

        #expect(visible.map(\.id) == [snoozed.id, done.id])
    }

    @Test("explicit snoozed and done folder lists show their matching state")
    func explicitSnoozedAndDoneFolderListsShowTheirMatchingState() {
        let now = Date(timeIntervalSince1970: 3000)
        let active = Self.header(id: "active")
        let snoozed = Self.header(id: "snoozed")
        let done = Self.header(id: "done")
        let state = LocalMessageWorkflowStatePolicy.markingDone(
            [SourceMessageID(sourceID: source, messageID: done.id)],
            now: now,
            in: LocalMessageWorkflowStatePolicy.snoozing(
                SourceMessageID(sourceID: source, messageID: snoozed.id),
                until: now.addingTimeInterval(3600),
                now: now,
                in: .defaults
            )
        )

        #expect(LocalMessageWorkflowVisibilityPolicy.headers(
            [active, snoozed, done],
            sourceID: source,
            mode: .snoozed,
            state: state,
            now: now
        ).map(\.id) == [snoozed.id])

        #expect(LocalMessageWorkflowVisibilityPolicy.headers(
            [active, snoozed, done],
            sourceID: source,
            mode: .done,
            state: state,
            now: now
        ).map(\.id) == [done.id])
    }

    @Test("unified inbox filtering uses each item's source identity")
    func unifiedInboxFilteringUsesEachItemsSourceIdentity() {
        let now = Date(timeIntervalSince1970: 4000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.item(sourceID: source, folder: folder, messageID: "shared-id")
        let second = Self.item(sourceID: otherSource, folder: folder, messageID: "shared-id")
        let state = LocalMessageWorkflowStatePolicy.snoozing(
            SourceMessageID(sourceID: source, messageID: "shared-id"),
            until: now.addingTimeInterval(3600),
            now: now,
            in: .defaults
        )

        let visible = LocalMessageWorkflowVisibilityPolicy.items(
            [first, second],
            mode: .active,
            state: state,
            now: now
        )

        #expect(visible.map(\.id) == [second.id])
    }

    @Test("presentation time key changes at snooze and rolling-week boundaries")
    func presentationTimeKeyChangesAtTemporalBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let header = MessageHeader(
            id: "boundary",
            threadID: "thread-boundary",
            folderID: "inbox",
            from: Correspondent(email: "ada@example.org"),
            subject: "Boundary",
            snippet: "",
            date: now.addingTimeInterval(-604_795)
        )
        let state = LocalMessageWorkflowStatePolicy.snoozing(
            SourceMessageID(sourceID: source, messageID: header.id),
            until: now.addingTimeInterval(5),
            now: now,
            in: .defaults
        )
        let filter = MailboxFilterQuery(activeFilters: [.lastWeek])

        let before = MailboxListTemporalInvalidationKey.headers(
            [header],
            filter: filter,
            workflowMode: .active,
            workflowState: state,
            now: now
        )
        let after = MailboxListTemporalInvalidationKey.headers(
            [header],
            filter: filter,
            workflowMode: .active,
            workflowState: state,
            now: now.addingTimeInterval(10)
        )

        #expect(before != after)
        #expect(before.expiredSnoozeCount == 0)
        #expect(after.expiredSnoozeCount == 1)
        #expect(before.lastWeekIncludedCount == 1)
        #expect(after.lastWeekIncludedCount == 0)
    }

    private static func header(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: id,
            snippet: "",
            date: Date(timeIntervalSince1970: 0)
        )
    }

    private static func item(
        sourceID: MailSourceID,
        folder: Folder,
        messageID: String
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: sourceID,
            folder: folder,
            header: header(id: messageID),
            sourceTitle: "Personal",
            sourceSubtitle: "ada@example.org",
            archiveFolder: Folder(id: "archive", name: "Archive", role: .archive)
        )
    }
}
