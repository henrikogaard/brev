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

/// Component equivalent of MessageListView's current-input getter, not a hosted view.
@MainActor
final class NavigationSelectionAcceptanceFixture {
    var headers: [MessageHeader]
    var sourceID = MailSourceID(accountID: "synthetic", mailboxID: "mailbox")
    var workflowState = LocalMessageWorkflowState.defaults
    var filter = MailboxFilterQuery.none
    let navigation = MailNavigationState(selectedFolderID: "synthetic")
    private let cache = MessageListPresentationSnapshotCache()
    private let tracker = MailboxListTemporalInvalidationTracker()
    private let overrides: InboxCategoryOverrideStore
    private let defaults: UserDefaults
    private let suite: String
    private(set) var builds = 0
    private let calendar: Calendar

    init(count: Int) {
        suite = "NavigationSelectionAcceptance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        overrides = InboxCategoryOverrideStore(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        let now = Date()
        headers = (0 ..< count).map { index in
            MessageHeader(id: "synthetic:\(index)", threadID: "thread-\(index / 3)", folderID: "synthetic",
                          from: Correspondent(email: "sender@example.test"), subject: "Synthetic \(index)",
                          snippet: "Synthetic preview", date: now.addingTimeInterval(-Double(index) * 30))
        }
    }

    func cleanup() { defaults.removePersistentDomain(forName: suite) }

    func replaceHeader(at index: Int, folderID: String? = nil, subject: String? = nil, snippet: String? = nil) {
        let old = headers[index]
        headers[index] = MessageHeader(
            id: old.id, threadID: old.threadID, folderID: folderID ?? old.folderID,
            from: old.from, subject: subject ?? old.subject, snippet: snippet ?? old.snippet, date: old.date
        )
    }

    func configureWorkflow() {
        filter = MailboxFilterQuery(activeFilters: [.lastWeek])
        let now = Date()
        for index in stride(from: 9, to: headers.count, by: 100) {
            workflowState = LocalMessageWorkflowStatePolicy.snoozing(
                SourceMessageID(sourceID: sourceID, messageID: headers[index].id),
                until: now.addingTimeInterval(3600), now: now, in: workflowState
            )
        }
    }

    func selectionHeaders() -> [MessageHeader] {
        presentation().navigationHeaders
    }

    func presentation() -> MessageListPresentationSnapshot {
        let now = Date()
        let temporalKey = tracker.key(headers: headers, filter: filter, workflowMode: .active,
                                      workflowState: workflowState, now: now)
        let key = MessageListPresentationSnapshotCache.Key(
            groupByThread: true, pinnedMessageIDs: [], mailboxFilter: filter,
            workflowSourceID: sourceID, workflowVisibilityMode: .active, workflowState: workflowState,
            sourceID: sourceID, activeInboxCategory: .all,
            inboxClassificationModeRaw: InboxClassificationMode.off.rawValue, inboxCategoryOverrideRevision: 0,
            mailboxSortOrder: .newestFirst, groupByDate: true, collapsedDateSectionIDs: [],
            temporalInvalidationKey: temporalKey, calendarDay: calendar.startOfDay(for: now),
            calendarIdentifier: calendar.identifier, calendarTimeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: "en_US_POSIX", supportsThreadGrouping: true
        )
        return cache.snapshot(for: key, headers: headers) {
            builds += 1
            let visible = workflowHeaders(now: now)
            let sorted = MessageListSortPolicy.sorted(
                MessageListVisibleHeaders.headers(from: visible, groupByThread: true), by: .newestFirst, pinnedIDs: []
            )
            return MessageListPresentationSnapshot(
                headers: sorted, pinnedMessageIDs: [], groupByDate: true, collapsedDateSectionIDs: [],
                referenceDate: now, calendar: calendar, sourceHeaders: headers,
                navigationHeaders: MessageListNavigationHeaders.headers(from: visible, threadContext: headers),
                sourceID: sourceID, groupsThreads: true
            )
        }
    }

    func workflowHeaders(now: Date) -> [MessageHeader] {
        let filtered = MessageListSortPolicy.filtered(headers, by: filter, now: now, calendar: calendar)
        let visible = LocalMessageWorkflowVisibilityPolicy.headers(
            filtered, sourceID: sourceID, mode: .active, state: workflowState, now: now
        )
        return InboxClassificationVisibilityPolicy.headers(
            visible, sourceID: sourceID, selectedCategory: .all, settings: .defaults, overrideStore: overrides
        )
    }
}
