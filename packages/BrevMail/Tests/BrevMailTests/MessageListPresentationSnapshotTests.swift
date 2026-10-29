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
        let key = Self.key(collapsedDateSectionIDs: [])

        _ = cache.snapshot(for: key, headers: headers) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: [])
        }
        _ = cache.snapshot(for: key, headers: headers) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: [])
        }
        #expect(buildCount == 1)

        // An equal-valued but different buffer is a miss — identity, not
        // deep equality, is the reuse check.
        _ = cache.snapshot(for: key, headers: headers.map { $0 }) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: [])
        }
        #expect(buildCount == 2)

        _ = cache.snapshot(
            for: Self.key(collapsedDateSectionIDs: ["Today"]),
            headers: headers
        ) {
            buildCount += 1
            return Self.snapshot(headers: headers, collapsedDateSectionIDs: ["Today"])
        }
        #expect(buildCount == 3)
    }

    @Test("unread and pinned tallies are derived over the source headers")
    func derivesFolderStatsCountsOverSourceHeaders() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        var unread = Self.header(id: "unread", date: referenceDate)
        unread.isRead = false
        var read = Self.header(id: "read", date: referenceDate)
        read.isRead = true
        var hidden = Self.header(id: "hidden", date: referenceDate)
        hidden.isRead = false
        let sourceHeaders = [unread, read, hidden]

        let snapshot = MessageListPresentationSnapshot(
            headers: [unread, read],
            pinnedMessageIDs: [unread.id, hidden.id],
            groupByDate: false,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate,
            sourceHeaders: sourceHeaders
        )

        #expect(snapshot.unreadHeaderCount == 2)
        #expect(snapshot.pinnedHeaderCount == 2)
    }

    @Test("headers group by thread oldest to newest for expanded rows")
    func groupsHeadersByThreadID() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let parent = Self.header(id: "parent", threadID: "thread-a", date: referenceDate)
        let oldest = Self.header(
            id: "oldest",
            threadID: "thread-a",
            date: referenceDate.addingTimeInterval(-3600)
        )
        let other = Self.header(id: "other", threadID: "thread-b", date: referenceDate)

        let snapshot = MessageListPresentationSnapshot(
            headers: [parent],
            pinnedMessageIDs: [],
            groupByDate: false,
            collapsedDateSectionIDs: [],
            referenceDate: referenceDate,
            sourceHeaders: [parent, oldest, other]
        )

        // Same result the per-render `ThreadMessageDerivation` filter
        // produced, without re-walking the folder.
        #expect(snapshot.headersByThreadID["thread-a"]?.map(\.id) == ["oldest", "parent"])
        #expect(snapshot.headersByThreadID["thread-b"]?.map(\.id) == ["other"])
    }

    @Test("selection refreshes retained navigation at snooze expiry and clock rollback")
    @MainActor
    func selectionAtSnoozeBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let headers = [Self.header(id: "active", date: now), Self.header(id: "wake", date: now)]
        let fixture = SelectionProjection(headers: headers)
        let state = LocalMessageWorkflowStatePolicy.snoozing(
            SourceMessageID(sourceID: fixture.sourceID, messageID: "wake"),
            until: now.addingTimeInterval(5), now: now, in: .defaults
        )
        let before = fixture.select(headers[0], now: now, state: state)
        let retained = fixture.select(headers[0], now: now.addingTimeInterval(4), state: state)
        #expect(before.navigationHeaders.map(\.id) == ["active"])
        #expect(retained.navigationHeaders.sharesRetainedBuffer(with: before.navigationHeaders))
        #expect(fixture.buildCount == 1)

        _ = fixture.select(headers[1], now: now.addingTimeInterval(5), state: state)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["active", "wake"])
        #expect(fixture.navigation.selectedHeader?.id == "wake")
        #expect(fixture.buildCount == 2)

        _ = fixture.select(headers[0], now: now, state: state)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["active"])
        #expect(fixture.buildCount == 3)
    }

    @Test("selection drops a message exactly at the rolling-week boundary")
    @MainActor
    func selectionAtRollingWeekBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let headers = [Self.header(id: "current", date: now),
                       Self.header(id: "expires", date: now.addingTimeInterval(-604_795))]
        let fixture = SelectionProjection(headers: headers)
        let filter = MailboxFilterQuery(activeFilters: [.lastWeek])
        _ = fixture.select(headers[1], now: now, filter: filter)
        #expect(fixture.navigation.selectedHeader?.id == "expires")
        _ = fixture.select(headers[0], now: now.addingTimeInterval(5), filter: filter)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["current"])
        #expect(fixture.navigation.selectedHeader?.id == "current")
        #expect(fixture.buildCount == 2)
    }

    @Test("selection refreshes Today membership and date sections across calendar midnight")
    @MainActor
    func selectionAtCalendarMidnight() {
        let calendar = Self.calendar
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let before = midnight.addingTimeInterval(-1)
        let headers = [Self.header(id: "yesterday", date: before),
                       Self.header(id: "today", date: midnight)]
        let fixture = SelectionProjection(headers: headers)
        let filter = MailboxFilterQuery(activeFilters: [.today])
        let old = fixture.select(headers[0], now: before, filter: filter)
        #expect(old.navigationHeaders.map(\.id) == ["yesterday"])
        let current = fixture.select(headers[1], now: midnight, filter: filter)
        #expect(current.navigationHeaders.map(\.id) == ["today"])
        #expect(current.dateSections.first?.visibleHeaders.map(\.id) == ["today"])
        #expect(fixture.navigation.selectedHeader?.id == "today")
        #expect(fixture.buildCount == 2)
    }

    @Test("selection reads current workflow state and undo without a header reload")
    @MainActor
    func selectionAfterWorkflowChange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let headers = [Self.header(id: "active", date: now), Self.header(id: "done", date: now)]
        let fixture = SelectionProjection(headers: headers)
        let initial = fixture.select(headers[1], now: now)
        let state = LocalMessageWorkflowStatePolicy.markingDone(
            [SourceMessageID(sourceID: fixture.sourceID, messageID: "done")], now: now, in: .defaults
        )
        _ = fixture.select(headers[0], now: now, state: state)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["active"])
        #expect(fixture.navigation.selectedHeader?.id == "active")
        _ = fixture.select(headers[1], now: now)
        #expect(fixture.navigation.currentFolderHeaders == initial.navigationHeaders)
        #expect(fixture.navigation.selectedHeader?.id == "done")
        #expect(fixture.buildCount == 3)
    }

    @Test("grouping capability changes invalidate filtered parent and reply navigation", arguments: [false, true])
    @MainActor
    func selectionAfterGroupingCapabilityChange(sourceOwned: Bool) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var parent = Self.header(id: "parent", threadID: "thread", date: now)
        parent.isFlagged = true
        let reply = Self.header(id: "reply", threadID: "thread", date: now.addingTimeInterval(-1))
        let other = Self.header(id: "other", date: now)
        let fixture = SelectionProjection(headers: [parent, reply, other])
        let filter = MailboxFilterQuery(activeFilters: [.flagged])
        _ = fixture.select(parent, now: now, filter: filter, supportsThreadGrouping: false, sourceOwned: sourceOwned)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["parent"])
        let grouped = fixture.select(parent, now: now, filter: filter, sourceOwned: sourceOwned)
        #expect(grouped.headers.map(\.id) == ["parent"])
        #expect(grouped.navigationHeaders.map(\.id) == ["parent", "reply"])
        _ = fixture.select(reply, now: now, filter: filter, sourceOwned: sourceOwned)
        #expect(fixture.navigation.selectedHeader?.id == "reply")
        #expect(fixture.navigation.currentFolderHeaders.sharesRetainedBuffer(with: grouped.navigationHeaders))
        #expect(fixture.navigation.readerExpansionSelectionID == "reply")
        #expect(fixture.buildCount == 2)
        _ = fixture.select(parent, now: now, filter: filter, supportsThreadGrouping: false, sourceOwned: sourceOwned)
        #expect(fixture.navigation.currentFolderHeaders.map(\.id) == ["parent"])
        #expect(fixture.navigation.selectedHeader?.id == "parent")
        #expect(fixture.buildCount == 3)
    }

    @MainActor
    private final class SelectionProjection {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        let headers: [MessageHeader]
        let navigation = MailNavigationState(selectedFolderID: "inbox")
        let cache = MessageListPresentationSnapshotCache()
        let tracker = MailboxListTemporalInvalidationTracker()
        var buildCount = 0

        init(headers: [MessageHeader]) { self.headers = headers }

        func select(
            _ header: MessageHeader,
            now: Date,
            filter: MailboxFilterQuery = .none,
            state: LocalMessageWorkflowState = .defaults,
            supportsThreadGrouping: Bool = true,
            sourceOwned: Bool = false
        ) -> MessageListPresentationSnapshot {
            let calendar = MessageListPresentationSnapshotTests.calendar
            let key = MessageListPresentationSnapshotTests.key(
                collapsedDateSectionIDs: [], filter: filter, workflowState: state,
                temporalKey: tracker.key(headers: headers, filter: filter, workflowMode: .active,
                                         workflowState: state, now: now),
                calendarDay: calendar.startOfDay(for: now), supportsThreadGrouping: supportsThreadGrouping
            )
            let snapshot = cache.snapshot(for: key, headers: headers) {
                buildCount += 1
                let filtered = MessageListSortPolicy.filtered(headers, by: filter, now: now, calendar: calendar)
                let visible = LocalMessageWorkflowVisibilityPolicy.headers(
                    filtered, sourceID: sourceID, mode: .active, state: state, now: now
                )
                return MessageListPresentationSnapshot(
                    headers: MessageListVisibleHeaders.headers(from: visible, groupByThread: true),
                    pinnedMessageIDs: [], groupByDate: true, collapsedDateSectionIDs: [],
                    referenceDate: now, calendar: calendar, sourceHeaders: headers,
                    navigationHeaders: MessageListNavigationHeaders.headers(
                        from: visible, threadContext: supportsThreadGrouping ? headers : []
                    )
                )
            }
            if sourceOwned {
                navigation.selectMessage(header, in: sourceID, headers: snapshot.navigationHeaders)
            } else {
                navigation.selectMessage(header, from: snapshot.navigationHeaders)
            }
            return snapshot
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func key(
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        filter: MailboxFilterQuery = .none,
        workflowState: LocalMessageWorkflowState = .defaults,
        temporalKey: MailboxListTemporalInvalidationKey = .init(expiredSnoozeCount: 0, lastWeekIncludedCount: 0),
        calendarDay: Date = Date(timeIntervalSince1970: 1_800_000_000),
        supportsThreadGrouping: Bool = true
    ) -> MessageListPresentationSnapshotCache.Key {
        let sourceID = MailSourceID(accountID: "account", mailboxID: "mailbox")
        return MessageListPresentationSnapshotCache.Key(
            groupByThread: true,
            pinnedMessageIDs: [],
            mailboxFilter: filter,
            workflowSourceID: sourceID,
            workflowVisibilityMode: .active,
            workflowState: workflowState,
            sourceID: sourceID,
            activeInboxCategory: .all,
            inboxClassificationModeRaw: InboxClassificationMode.off.rawValue,
            inboxCategoryOverrideRevision: 0,
            mailboxSortOrder: .newestFirst,
            groupByDate: true,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            temporalInvalidationKey: temporalKey,
            calendarDay: calendarDay,
            calendarIdentifier: .gregorian,
            calendarTimeZoneIdentifier: "UTC",
            localeIdentifier: "en_US_POSIX",
            supportsThreadGrouping: supportsThreadGrouping
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

    private static func header(
        id: String,
        threadID: String? = nil,
        date: Date
    ) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID ?? id,
            folderID: "inbox",
            from: Correspondent(email: "sender@example.org"),
            subject: id,
            snippet: "Preview",
            date: date
        )
    }
}
