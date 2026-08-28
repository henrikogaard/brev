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
import BrevSettings
import Foundation
import Testing

@Suite("Message list presentation snapshot")
struct MessageListPresentationSnapshotTests {
    @Test("snapshot derives indexes and collapsed date sections once")
    func derivesIndexesAndDateSections() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let first = Self.header(id: "first", date: referenceDate)
        let second = Self.header(id: "second", date: referenceDate.addingTimeInterval(-60))

        let snapshot = MessageListPresentationSnapshot(
            headers: [first, second],
            pinnedMessageIDs: [first.id],
            groupByDate: true,
            collapsedDateSectionIDs: ["Pinned"],
            referenceDate: referenceDate
        )

        #expect(snapshot.visibleIndex(for: first.id) == 0)
        #expect(snapshot.visibleIndex(for: second.id) == 1)
        let pinned = try #require(snapshot.dateSections.first)
        #expect(pinned.title == "Pinned")
        #expect(pinned.visibleHeaders.isEmpty)
    }

    @Test("cache reuses a projection until a presentation input changes")
    func cacheReusesProjection() {
        let headers = [Self.header(id: "first", date: Date(timeIntervalSince1970: 1_800_000_000))]
        let cache = MessageListPresentationSnapshotCache()
        var buildCount = 0
        let key = Self.key(headers: headers, collapsedDateSectionIDs: [])

        _ = cache.snapshot(for: key) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: [])
        }
        _ = cache.snapshot(for: key) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: [])
        }
        #expect(buildCount == 1)

        _ = cache.snapshot(for: Self.key(headers: headers, collapsedDateSectionIDs: ["Today"])) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: ["Today"])
        }
        #expect(buildCount == 2)
    }

    private static func key(
        headers: [MessageHeader],
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>
    ) -> MessageListPresentationSnapshotCache.Key {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        return MessageListPresentationSnapshotCache.Key(
            headers: headers,
            groupByThread: true,
            pinnedMessageIDs: [],
            mailboxFilter: .none,
            workflowSourceID: sourceID,
            workflowVisibilityMode: .active,
            workflowState: .defaults,
            sourceID: sourceID,
            activeInboxCategory: .all,
            inboxClassificationModeRaw: InboxClassificationMode.off.rawValue,
            inboxCategoryOverrideRevision: 0,
            mailboxSortOrder: .newestFirst,
            groupByDate: true,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            temporalInvalidationKey: MailboxListTemporalInvalidationKey(
                expiredSnoozeCount: 0,
                lastWeekIncludedCount: 0
            ),
            calendarDay: Date(timeIntervalSince1970: 1_800_000_000),
            calendarIdentifier: .gregorian,
            calendarTimeZoneIdentifier: "UTC",
            localeIdentifier: "en_US_POSIX"
        )
    }

    private static func snapshot(
        headers: [MessageHeader],
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>
    ) -> MessageListPresentationSnapshot {
        MessageListPresentationSnapshot(
            headers: headers,
            pinnedMessageIDs: [],
            groupByDate: true,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func header(id: String, date: Date) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(email: "sender@example.org"),
            subject: id,
            snippet: "Preview",
            date: date
        )
    }
}
