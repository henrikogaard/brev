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
import BrevDesign
@testable import BrevMail
import Foundation
import Testing

@Suite("Unified Inbox presentation snapshot")
struct UnifiedInboxPresentationSnapshotTests {
    @Test("collapsed and expanded selections are source-owned and capability gated", arguments: [true, false])
    func visibleThreadSelection(grouped: Bool) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        func item(_ id: String, account: String = "personal", mailbox: String = "primary",
                  thread: String = "thread") -> UnifiedInboxItem {
            Self.item(accountID: account, mailboxID: mailbox, folder: folder, messageID: id,
                      subject: id, date: now, threadID: thread)
        }
        let parent = item("parent")
        let child = item("child")
        let foreign = item("child", account: "work")
        let otherMailbox = item("child", mailbox: "other")
        let otherThread = item("other", thread: "other-thread")
        let key = UnifiedInboxThreadGrouping.key(for: parent)
        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [foreign, parent], pinnedMessageIDs: [], groupByDate: false, collapsedDateSectionIDs: [],
            threadCounts: grouped ? [key: 2] : [:], sourceItems: [parent, child, foreign, otherMailbox, otherThread]
        )
        func row(_ item: UnifiedInboxItem, expanded: Set<String> = []) -> String? {
            snapshot.selectedRowID(selectedMessageID: item.header.id, selectedSourceID: item.sourceID,
                                   expandedThreadIDs: expanded)
        }
        #expect(row(child) == (grouped ? parent.id : nil))
        #expect(row(child, expanded: [key]) == (grouped ? child.id : nil))
        #expect(row(parent) == parent.id)
        #expect(row(parent, expanded: [key]) == parent.id)
        #expect(row(foreign, expanded: [key]) == foreign.id)
        #expect(row(otherMailbox) == nil)
        #expect(row(otherThread) == nil)
        #expect(snapshot.selectedRowID(selectedMessageID: nil, selectedSourceID: parent.sourceID,
                                       expandedThreadIDs: []) == nil)
        #expect(snapshot.selectedRowID(selectedMessageID: child.header.id, selectedSourceID: nil,
                                       expandedThreadIDs: []) == nil)
    }

    @Test("unified selection uses displayed representative and rejects removed or date-hidden rows")
    func filteredSelectionRepresentative() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let first = Self.item(accountID: "personal", mailboxID: "primary", folder: folder,
                              messageID: "first", subject: "First", date: now, threadID: "thread")
        let second = Self.item(accountID: "personal", mailboxID: "primary", folder: folder,
                               messageID: "second", subject: "Second", date: now, threadID: "thread")
        let key = UnifiedInboxThreadGrouping.key(for: first)
        func row(visible: [UnifiedInboxItem], source: [UnifiedInboxItem], collapsed: Set<String> = [],
                 count: Int = 2, expanded: Set<String> = []) -> String? {
            let snapshot = UnifiedInboxPresentationSnapshot(
                visibleItems: visible, pinnedMessageIDs: [second.pinID], groupByDate: true,
                collapsedDateSectionIDs: collapsed, referenceDate: now,
                threadCounts: [key: count], sourceItems: source
            )
            return snapshot.selectedRowID(selectedMessageID: first.header.id, selectedSourceID: first.sourceID,
                                          expandedThreadIDs: expanded)
        }
        #expect(row(visible: [second], source: [first, second]) == second.id)
        #expect(row(visible: [first], source: [second, first]) == first.id)
        #expect(row(visible: [second], source: [first, second], collapsed: ["Pinned"]) == nil)
        #expect(row(visible: [second], source: [second]) == nil)
        #expect(row(visible: [second, first], source: [first, second]) == first.id)
        #expect(row(visible: [second], source: [first, second], count: 1, expanded: [key]) == second.id)
    }

    @Test("date sections preserve source identity when message IDs collide")
    func dateSectionsPreserveSourceIdentityWhenMessageIDsCollide() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let personal = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "shared-provider-id",
            subject: "Personal message",
            date: referenceDate
        )
        let work = Self.item(
            accountID: "work",
            mailboxID: "primary",
            folder: folder,
            messageID: "shared-provider-id",
            subject: "Work message",
            date: referenceDate.addingTimeInterval(-60)
        )

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [personal, work],
            pinnedMessageIDsRaw: "",
            groupByDate: true,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate
        )
        let section = try #require(snapshot.dateSections.first)

        #expect(section.visibleItems.map(\.id) == [personal.id, work.id])
        #expect(section.visibleItems.map(\.header.subject) == ["Personal message", "Work message"])
        #expect(snapshot.visibleIndex(for: personal.id) == 0)
        #expect(snapshot.visibleIndex(for: work.id) == 1)
    }

    @Test("pinned IDs are parsed once and collapsed pinned sections hide their rows")
    func pinnedIDsAndCollapsedSectionsAreDerivedTogether() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let pinned = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "pinned",
            subject: "Pinned message",
            date: referenceDate
        )
        let regular = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "regular",
            subject: "Regular message",
            date: referenceDate.addingTimeInterval(-60)
        )

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [pinned, regular],
            pinnedMessageIDsRaw: pinned.pinID,
            groupByDate: true,
            collapsedDateSectionIDs: ["Pinned"],
            referenceDate: referenceDate
        )
        let pinnedSection = try #require(snapshot.dateSections.first)
        let regularSection = try #require(snapshot.dateSections.dropFirst().first)

        #expect(snapshot.pinnedMessageIDs == [pinned.pinID])
        #expect(pinnedSection.title == "Pinned")
        #expect(pinnedSection.totalCount == 1)
        #expect(pinnedSection.isCollapsed)
        #expect(pinnedSection.visibleItems.isEmpty)
        #expect(regularSection.visibleItems.map(\.id) == [regular.id])
    }

    @Test("wake date overrides group by the effective date without changing message timestamps")
    func wakeDateOverridesDriveUnifiedDateSections() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let oldDate = referenceDate.addingTimeInterval(-16 * 86400)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let woken = Self.item(
            accountID: "personal",
            mailboxID: "primary",
            folder: folder,
            messageID: "woken",
            subject: "Woken message",
            date: oldDate
        )
        let sourceMessageID = SourceMessageID(sourceID: woken.sourceID, messageID: woken.header.id)
        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [woken],
            pinnedMessageIDs: [],
            groupByDate: true,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate,
            effectiveDateOverrides: [sourceMessageID: referenceDate]
        )
        let section = try #require(snapshot.dateSections.first)

        #expect(section.title == "Today")
        #expect(section.visibleItems.map(\.id) == [woken.id])
        #expect(snapshot.visibleItems.first?.header.date == oldDate)
    }

    @Test("collapsed provider threads use visible wake priority without spreading RFC snooze state")
    func collapsedThreadWakePriorityIsAggregatedOnlyForDisplayedRows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let wakeAt = now.addingTimeInterval(-1800)
        let newerWakeAt = now.addingTimeInterval(-300)
        let singletonWakeAt = now.addingTimeInterval(-900)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let sourceA = MailSourceID(accountID: "personal", mailboxID: "primary")
        let sourceB = MailSourceID(accountID: "work", mailboxID: "primary")

        func item(
            sourceID: MailSourceID,
            id: String,
            rfcID: String,
            threadID: String,
            date: Date
        ) -> UnifiedInboxItem {
            UnifiedInboxItem(
                sourceID: sourceID,
                folder: folder,
                header: MessageHeader(
                    id: id,
                    threadID: threadID,
                    folderID: folder.id,
                    from: Correspondent(email: "sender@example.org"),
                    date: date,
                    messageID: rfcID
                ),
                sourceTitle: sourceID.accountID,
                sourceSubtitle: "\(sourceID.accountID)@example.org",
                archiveFolder: nil
            )
        }

        let representative = item(
            sourceID: sourceA,
            id: "representative",
            rfcID: "representative@example.org",
            threadID: "provider-thread",
            date: now.addingTimeInterval(-600)
        )
        let wakeMember = item(
            sourceID: sourceA,
            id: "shared-provider-id",
            rfcID: "wake-member@example.org",
            threadID: "provider-thread",
            date: now.addingTimeInterval(-86400)
        )
        let sourceCollision = item(
            sourceID: sourceB,
            id: "shared-provider-id",
            rfcID: "foreign@example.org",
            threadID: "provider-thread",
            date: now.addingTimeInterval(-2400)
        )
        let newerWakeRepresentative = item(
            sourceID: sourceA,
            id: "newer-wake-representative",
            rfcID: "newer-wake-representative@example.org",
            threadID: "newer-wake-thread",
            date: now.addingTimeInterval(-100_000)
        )
        let newerWakeMember = item(
            sourceID: sourceA,
            id: "newer-wake-member",
            rfcID: "newer-wake-member@example.org",
            threadID: "newer-wake-thread",
            date: now.addingTimeInterval(-200_000)
        )
        let singleton = item(
            sourceID: sourceA,
            id: "singleton",
            rfcID: "singleton@example.org",
            threadID: "singleton-thread",
            date: now.addingTimeInterval(-300_000)
        )
        let ordinary = item(
            sourceID: sourceA,
            id: "ordinary",
            rfcID: "ordinary@example.org",
            threadID: "ordinary-thread",
            date: now.addingTimeInterval(-1200)
        )
        let pinned = item(
            sourceID: sourceA,
            id: "pinned",
            rfcID: "pinned@example.org",
            threadID: "pinned-thread",
            date: now.addingTimeInterval(-100_000)
        )
        let allVisibleItems = [
            representative, wakeMember, sourceCollision, ordinary, pinned,
            newerWakeRepresentative, newerWakeMember, singleton,
        ]
        let wakeMemberID = SourceMessageID(sourceID: sourceA, messageID: wakeMember.header.id)
        let representativeID = SourceMessageID(sourceID: sourceA, messageID: representative.header.id)
        let sourceCollisionID = SourceMessageID(sourceID: sourceB, messageID: sourceCollision.header.id)
        let individualWakeDates = MessageListSnoozeWakePolicy.effectiveDateOverrides(
            for: allVisibleItems.map { item in
                MessageListSnoozeWakeEntry(
                    sourceMessageID: SourceMessageID(sourceID: item.sourceID, messageID: item.header.id),
                    headerDate: item.header.date,
                    threadID: item.header.threadID,
                    header: item.header
                )
            },
            snoozes: [
                LocalMessageSnooze(
                    messageID: wakeMemberID,
                    wakeAt: wakeAt,
                    conversationMetadata: .init(rfcIdentifiers: ["wake-member@example.org"])
                ),
                LocalMessageSnooze(
                    messageID: SourceMessageID(sourceID: sourceA, messageID: newerWakeMember.header.id),
                    wakeAt: newerWakeAt,
                    conversationMetadata: .init(rfcIdentifiers: ["newer-wake-member@example.org"])
                ),
                LocalMessageSnooze(
                    messageID: SourceMessageID(sourceID: sourceA, messageID: singleton.header.id),
                    wakeAt: singletonWakeAt,
                    conversationMetadata: .init(rfcIdentifiers: ["singleton@example.org"])
                )
            ],
            now: now
        )
        let pinnedIDs: Set<MessageHeader.ID> = [pinned.pinID]
        let sortedItems = MessageListSortPolicy.sortedItems(
            allVisibleItems,
            by: .newestFirst,
            pinnedIDs: pinnedIDs,
            dateOverrides: individualWakeDates
        )
        let threadCounts = UnifiedInboxThreadGrouping.counts(for: sortedItems) { _ in true }
        let collapsedRows = UnifiedInboxThreadGrouping.sortedParents(
            from: sortedItems,
            counts: threadCounts,
            by: .newestFirst,
            pinnedIDs: pinnedIDs,
            effectiveDateOverrides: individualWakeDates
        )
        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: collapsedRows.items,
            pinnedMessageIDs: pinnedIDs,
            groupByDate: true,
            collapsedDateSectionIDs: [],
            referenceDate: now,
            threadCounts: threadCounts,
            sourceItems: allVisibleItems,
            effectiveDateOverrides: individualWakeDates,
            displayDateOverrides: collapsedRows.dateOverrides
        )
        let representativeThreadKey = UnifiedInboxThreadGrouping.key(for: representative)
        let sourceCollisionThreadKey = UnifiedInboxThreadGrouping.key(for: sourceCollision)

        #expect(snapshot.visibleItems.map(\.id) == [
            pinned.id,
            newerWakeMember.id,
            representative.id,
            singleton.id,
            ordinary.id,
            sourceCollision.id,
        ])
        #expect(individualWakeDates[wakeMemberID] == wakeAt)
        #expect(individualWakeDates[representativeID] == nil)
        #expect(individualWakeDates[sourceCollisionID] == nil)
        #expect(snapshot.itemsByThreadKey[representativeThreadKey]?.map(\.id) == [
            wakeMember.id,
            representative.id,
        ])
        #expect(snapshot.itemsByThreadKey[sourceCollisionThreadKey]?.map(\.id) == [sourceCollision.id])
        #expect(individualWakeDates[SourceMessageID(sourceID: sourceA, messageID: newerWakeRepresentative.header.id)] == nil)
        #expect(individualWakeDates[SourceMessageID(sourceID: sourceA, messageID: newerWakeMember.header.id)] == newerWakeAt)

        let senderSorted = MessageListSortPolicy.sortedItems(
            allVisibleItems,
            by: .sender,
            pinnedIDs: pinnedIDs
        )
        let senderCounts = UnifiedInboxThreadGrouping.counts(for: senderSorted) { _ in true }
        #expect(UnifiedInboxThreadGrouping.sortedParents(
            from: senderSorted,
            counts: senderCounts,
            by: .sender,
            pinnedIDs: pinnedIDs,
            effectiveDateOverrides: individualWakeDates
        ).items.map(\.id) == UnifiedInboxThreadGrouping.parents(from: senderSorted, counts: senderCounts).map(\.id))
    }

    @Test("unread and pinned tallies are derived over the source items")
    func derivesFolderStatsCountsOverSourceItems() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        var unread = Self.item(
            accountID: "personal", mailboxID: "primary", folder: folder,
            messageID: "unread", subject: "Unread", date: referenceDate
        )
        unread.header.isRead = false
        var read = Self.item(
            accountID: "personal", mailboxID: "primary", folder: folder,
            messageID: "read", subject: "Read", date: referenceDate
        )
        read.header.isRead = true
        var hidden = Self.item(
            accountID: "work", mailboxID: "primary", folder: folder,
            messageID: "hidden", subject: "Hidden", date: referenceDate
        )
        hidden.header.isRead = false
        let sourceItems = [unread, read, hidden]

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [unread, read],
            pinnedMessageIDs: [unread.pinID, hidden.pinID],
            groupByDate: false,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate,
            sourceItems: sourceItems
        )

        #expect(snapshot.unreadItemCount == 2)
        #expect(snapshot.pinnedItemCount == 2)
    }

    @Test("items group by thread key oldest to newest for expanded rows")
    func groupsItemsByThreadKey() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let parent = Self.item(
            accountID: "personal", mailboxID: "primary", folder: folder,
            messageID: "parent", subject: "Parent", date: referenceDate,
            threadID: "thread-a"
        )
        let oldest = Self.item(
            accountID: "personal", mailboxID: "primary", folder: folder,
            messageID: "oldest", subject: "Oldest",
            date: referenceDate.addingTimeInterval(-3600),
            threadID: "thread-a"
        )
        // Same threadID on another source must land in its own bucket.
        let foreign = Self.item(
            accountID: "work", mailboxID: "primary", folder: folder,
            messageID: "foreign", subject: "Foreign", date: referenceDate,
            threadID: "thread-a"
        )

        let snapshot = UnifiedInboxPresentationSnapshot(
            visibleItems: [parent],
            pinnedMessageIDs: [],
            groupByDate: false,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate,
            sourceItems: [parent, oldest, foreign]
        )

        let threadKey = UnifiedInboxThreadGrouping.key(for: parent)
        let foreignKey = UnifiedInboxThreadGrouping.key(for: foreign)
        #expect(threadKey != foreignKey)
        #expect(snapshot.itemsByThreadKey[threadKey]?.map(\.id) == [oldest.id, parent.id])
        #expect(snapshot.itemsByThreadKey[foreignKey]?.map(\.id) == [foreign.id])
    }

    private static func item(
        accountID: String,
        mailboxID: String,
        folder: Folder,
        messageID: String,
        subject: String,
        date: Date,
        threadID: String? = nil
    ) -> UnifiedInboxItem {
        UnifiedInboxItem(
            sourceID: MailSourceID(accountID: accountID, mailboxID: mailboxID),
            folder: folder,
            header: MessageHeader(
                id: messageID,
                threadID: threadID ?? messageID,
                folderID: folder.id,
                from: Correspondent(email: "sender@example.org"),
                subject: subject,
                snippet: "Preview",
                date: date
            ),
            sourceTitle: accountID,
            sourceSubtitle: "\(accountID)@example.org",
            archiveFolder: nil
        )
    }
}
