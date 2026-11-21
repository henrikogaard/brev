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

@Suite("MessageListSortPolicy")
struct MessageListSortPolicyTests {
    @Test("newestFirst sorts descending by date")
    func newestFirstSortsDescending() {
        let headers = [
            Self.makeHeader(id: "old", date: Date(timeIntervalSince1970: 100)),
            Self.makeHeader(id: "new", date: Date(timeIntervalSince1970: 200))
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .newestFirst, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["new", "old"])
    }

    @Test("oldestFirst sorts ascending by date")
    func oldestFirstSortsAscending() {
        let headers = [
            Self.makeHeader(id: "new", date: Date(timeIntervalSince1970: 200)),
            Self.makeHeader(id: "old", date: Date(timeIntervalSince1970: 100))
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .oldestFirst, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["old", "new"])
    }

    @Test("equal dates fall back to message id for deterministic order")
    func equalDatesFallBackToMessageID() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let headers = [
            Self.makeHeader(id: "b", date: sameDate),
            Self.makeHeader(id: "a", date: sameDate)
        ]

        let sorted = MessageListSortPolicy.sorted(headers, by: .newestFirst, pinnedIDs: [])

        #expect(sorted.map(\.id) == ["a", "b"])
    }

    @Test("sender sorts alphabetically by sender name")
    func senderSortsAlphabetically() {
        let headers = [
            Self.makeHeader(id: "z", from: "Zoe"),
            Self.makeHeader(id: "a", from: "Alice"),
            Self.makeHeader(id: "m", from: "Mike")
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .sender, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["a", "m", "z"])
    }

    @Test("sender ties fall back to newest date then message id")
    func senderTiesFallBackToNewestDateThenMessageID() {
        let date = Date(timeIntervalSince1970: 100)
        let headers = [
            Self.makeHeader(id: "b", date: date, from: "Alice"),
            Self.makeHeader(id: "newer", date: date.addingTimeInterval(100), from: "Alice"),
            Self.makeHeader(id: "a", date: date, from: "Alice")
        ]

        let sorted = MessageListSortPolicy.sorted(headers, by: .sender, pinnedIDs: [])

        #expect(sorted.map(\.id) == ["newer", "a", "b"])
    }

    @Test("subject sorts alphabetically by subject")
    func subjectSortsAlphabetically() {
        let headers = [
            Self.makeHeader(id: "c", subject: "Zebra"),
            Self.makeHeader(id: "a", subject: "Apple"),
            Self.makeHeader(id: "b", subject: "Mango")
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .subject, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }

    @Test("unreadFirst sorts unread before read, then by date")
    func unreadFirstSortsUnreadBeforeRead() {
        let now = Date()
        let headers = [
            Self.makeHeader(id: "read-old", isRead: true, date: now.addingTimeInterval(-100)),
            Self.makeHeader(id: "unread-old", isRead: false, date: now.addingTimeInterval(-200)),
            Self.makeHeader(id: "unread-new", isRead: false, date: now)
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .unreadFirst, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["unread-new", "unread-old", "read-old"])
    }

    @Test("flaggedFirst sorts flagged before unflagged, then by date")
    func flaggedFirstSortsFlaggedBeforeUnflagged() {
        let now = Date()
        let headers = [
            Self.makeHeader(id: "unflagged", isFlagged: false, date: now),
            Self.makeHeader(id: "flagged-old", isFlagged: true, date: now.addingTimeInterval(-100)),
            Self.makeHeader(id: "flagged-new", isFlagged: true, date: now)
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .flaggedFirst, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["flagged-new", "flagged-old", "unflagged"])
    }

    @Test("attachmentFirst sorts attachments before non-attachments")
    func attachmentFirstSortsAttachmentsBeforeNon() {
        let now = Date()
        let headers = [
            Self.makeHeader(id: "no-att", hasAttachments: false, date: now),
            Self.makeHeader(id: "att-old", hasAttachments: true, date: now.addingTimeInterval(-100)),
            Self.makeHeader(id: "att-new", hasAttachments: true, date: now)
        ]
        let sorted = MessageListSortPolicy.sorted(headers, by: .attachmentFirst, pinnedIDs: [])
        #expect(sorted.map(\.id) == ["att-new", "att-old", "no-att"])
    }

    @Test("pinned messages always appear first regardless of sort order")
    func pinnedMessagesAppearFirst() {
        let now = Date()
        let headers = [
            Self.makeHeader(id: "pinned-old", date: now.addingTimeInterval(-100)),
            Self.makeHeader(id: "unpinned-new", date: now),
            Self.makeHeader(id: "unpinned-old", date: now.addingTimeInterval(-200))
        ]
        let sorted = MessageListSortPolicy.sorted(
            headers, by: .newestFirst, pinnedIDs: ["pinned-old"]
        )
        #expect(sorted.map(\.id) == ["pinned-old", "unpinned-new", "unpinned-old"])
    }

    @Test("unified inbox items use the selected mailbox sort order")
    func unifiedInboxItemsUseSelectedMailboxSortOrder() {
        let items = [
            Self.makeItem(id: "z", from: "Zoe"),
            Self.makeItem(id: "a", from: "Ada"),
            Self.makeItem(id: "m", from: "Mina"),
        ]

        let sorted = MessageListSortPolicy.sortedItems(items, by: .sender, pinnedIDs: [])

        #expect(sorted.map(\.header.id) == ["a", "m", "z"])
    }

    @Test("unified inbox pinned items stay above the selected sort order")
    func unifiedInboxPinnedItemsStayAboveSelectedSortOrder() {
        let items = [
            Self.makeItem(id: "z", from: "Zoe"),
            Self.makeItem(id: "pinned", from: "Quinn"),
            Self.makeItem(id: "a", from: "Ada"),
        ]

        let sorted = MessageListSortPolicy.sortedItems(items, by: .sender, pinnedIDs: [items[1].pinID])

        #expect(sorted.map(\.header.id) == ["pinned", "a", "z"])
    }

    @Test("newer arrivals stay above woken older mail and pins keep precedence")
    func snoozeWakeDatesRespectNewestFirstAndPins() {
        let wokenDate = Date(timeIntervalSince1970: 100)
        let arrivalDate = Date(timeIntervalSince1970: 200)
        let wakeAt = Date(timeIntervalSince1970: 150)
        let woken = Self.makeHeader(id: "woken", date: wokenDate)
        let arrival = Self.makeHeader(id: "arrival", date: arrivalDate)
        let sorted = MessageListSortPolicy.sorted(
            [woken, arrival],
            by: .newestFirst,
            pinnedIDs: [],
            dateOverrides: [woken.id: wakeAt]
        )
        #expect(sorted.map(\.id) == ["arrival", "woken"])

        let pinned = Self.makeHeader(id: "pinned", date: wokenDate.addingTimeInterval(-50))
        let pinnedSorted = MessageListSortPolicy.sorted(
            [woken, arrival, pinned],
            by: .newestFirst,
            pinnedIDs: [pinned.id],
            dateOverrides: [woken.id: arrivalDate.addingTimeInterval(100)]
        )
        #expect(pinnedSorted.first?.id == pinned.id)
    }

    @Test("wake date overrides do not change other sort orders")
    func wakeDateOverridesDoNotChangeOtherSortOrders() {
        let older = Self.makeHeader(id: "older", date: Date(timeIntervalSince1970: 100))
        let newer = Self.makeHeader(id: "newer", date: Date(timeIntervalSince1970: 200))
        let sorted = MessageListSortPolicy.sorted(
            [newer, older],
            by: .oldestFirst,
            pinnedIDs: [],
            dateOverrides: [newer.id: Date(timeIntervalSince1970: 50)]
        )

        #expect(sorted.map(\.id) == ["older", "newer"])
    }

    @Test("equal wake dates prefer the newer original message as thread parent")
    func wakeDateTiesPreferNewestThreadMember() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let wakeAt = Date(timeIntervalSince1970: 300)
        let older = Self.makeHeader(id: "a", date: oldDate, threadID: "thread")
        let newer = Self.makeHeader(id: "z", date: newDate, threadID: "thread")
        let sorted = MessageListSortPolicy.sorted(
            [older, newer],
            by: .newestFirst,
            pinnedIDs: [],
            dateOverrides: [older.id: wakeAt, newer.id: wakeAt]
        )
        #expect(sorted.map(\.id) == ["z", "a"])

        let items = [
            Self.makeItem(id: "a", from: "Older", date: oldDate, threadID: "thread"),
            Self.makeItem(id: "z", from: "Newer", date: newDate, threadID: "thread"),
        ]
        let sourceID = items[0].sourceID
        let dateOverrides = Dictionary(
            uniqueKeysWithValues: ["a", "z"].map {
                (SourceMessageID(sourceID: sourceID, messageID: $0), wakeAt)
            }
        )
        let sortedItems = MessageListSortPolicy.sortedItems(
            items,
            by: .newestFirst,
            pinnedIDs: [],
            dateOverrides: dateOverrides
        )
        let counts = UnifiedInboxThreadGrouping.counts(for: sortedItems) { _ in true }
        let parents = UnifiedInboxThreadGrouping.parents(from: sortedItems, counts: counts)
        #expect(parents.map(\.header.id) == ["z"])
    }

    @Test("filter excludes non-matching headers")
    func filterExcludesNonMatching() {
        let headers = [
            Self.makeHeader(id: "read", isRead: true),
            Self.makeHeader(id: "unread", isRead: false),
            Self.makeHeader(id: "flagged-read", isRead: true, isFlagged: true)
        ]
        let filter = MailboxFilterQuery(activeFilters: [.unread], senderEmail: nil)
        let filtered = MessageListSortPolicy.filtered(headers, by: filter)
        #expect(filtered.map(\.id) == ["unread"])
    }

    private static func makeHeader(
        id: String,
        isRead: Bool = false,
        isFlagged: Bool = false,
        hasAttachments: Bool = false,
        date: Date = Date(),
        from name: String = "Test",
        subject: String = "Subject",
        threadID: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID ?? "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: name, email: "\(name.lowercased())@example.org"),
            subject: subject,
            snippet: "Preview",
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            hasAttachments: hasAttachments
        )
    }

    private static func makeItem(
        id: String,
        from name: String,
        date: Date = Date(),
        threadID: String? = nil
    ) -> UnifiedInboxItem {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        return UnifiedInboxItem(
            sourceID: sourceID,
            folder: folder,
            header: makeHeader(id: id, date: date, from: name, threadID: threadID),
            sourceTitle: "Mailbox",
            sourceSubtitle: "mailbox@example.org",
            archiveFolder: nil
        )
    }
}
