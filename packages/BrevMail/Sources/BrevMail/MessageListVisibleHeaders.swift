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
import BrevSettings
import Foundation

/// Reuses the folder-list projection across selection and other unrelated
/// SwiftUI invalidations. The key includes every input that changes filtering,
/// sorting, thread grouping, or date-section visibility.
final class MessageListPresentationSnapshotCache {
    struct Key: Equatable {
        let headers: [MessageHeader]
        let groupByThread: Bool
        let pinnedMessageIDs: Set<MessageHeader.ID>
        let mailboxFilter: MailboxFilterQuery
        let workflowSourceID: MailSourceID
        let workflowVisibilityMode: LocalMessageWorkflowVisibilityMode
        let workflowState: LocalMessageWorkflowState
        let sourceID: MailSourceID?
        let activeInboxCategory: InboxCategory
        let inboxClassificationModeRaw: String
        let inboxCategoryOverrideRevision: Int
        let mailboxSortOrder: MailboxSortOrder
        let groupByDate: Bool
        let collapsedDateSectionIDs: Set<MessageListDateSection.ID>
        let temporalInvalidationKey: MailboxListTemporalInvalidationKey
        let calendarDay: Date
        let calendarIdentifier: Calendar.Identifier
        let calendarTimeZoneIdentifier: String
        let localeIdentifier: String
    }

    private var key: Key?
    private var value: MessageListPresentationSnapshot?

    func snapshot(
        for key: Key,
        build: () -> MessageListPresentationSnapshot
    ) -> MessageListPresentationSnapshot {
        if self.key == key, let value {
            return value
        }
        let value = build()
        self.key = key
        self.value = value
        return value
    }
}

/// Fully derived data needed to render one folder's list.
struct MessageListPresentationSnapshot {
    let headers: [MessageHeader]
    let dateSections: [MessageListVisibleDateSection]

    private let visibleIndexesByHeaderID: [MessageHeader.ID: Int]

    init(
        headers: [MessageHeader],
        pinnedMessageIDs: Set<MessageHeader.ID>,
        groupByDate: Bool,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.headers = headers
        visibleIndexesByHeaderID = Dictionary(
            headers.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        dateSections = groupByDate
            ? MessageListSectionVisibility.sections(
                from: MessageListDateGrouping.sections(
                    for: headers,
                    pinnedIDs: pinnedMessageIDs,
                    referenceDate: referenceDate,
                    calendar: calendar
                ),
                collapsedIDs: collapsedDateSectionIDs
            )
            : []
    }

    func visibleIndex(for headerID: MessageHeader.ID) -> Int? {
        visibleIndexesByHeaderID[headerID]
    }
}

enum MessageListVisibleHeaders {
    static func headers(
        from headers: [MessageHeader],
        groupByThread: Bool,
        pinnedIDs: Set<MessageHeader.ID> = []
    ) -> [MessageHeader] {
        guard groupByThread else {
            return promotedPinnedHeaders(headers, pinnedIDs: pinnedIDs)
        }
        var seen = Set<String>()
        var result: [MessageHeader] = []
        result.reserveCapacity(headers.count)
        for header in headers where seen.insert(header.threadID).inserted {
            result.append(header)
        }
        return promotedPinnedHeaders(result, pinnedIDs: pinnedIDs)
    }

    private static func promotedPinnedHeaders(
        _ headers: [MessageHeader],
        pinnedIDs: Set<MessageHeader.ID>
    ) -> [MessageHeader] {
        guard !pinnedIDs.isEmpty else { return headers }
        let pinned = headers.filter { pinnedIDs.contains($0.id) }
        let unpinned = headers.filter { !pinnedIDs.contains($0.id) }
        return pinned + unpinned
    }
}

enum MessageListNavigationHeaders {
    static func headers(
        from headers: [MessageHeader],
        threadContext: [MessageHeader] = [],
        pinnedIDs: Set<MessageHeader.ID> = []
    ) -> [MessageHeader] {
        // A matching conversation exposes its replies inline, even when those
        // replies do not match the list filter. Keep the same context in the reader.
        let threadIDs = Set(headers.map(\.threadID))
        let matchedIDs = Set(headers.map(\.id))
        let replies = threadContext.filter {
            threadIDs.contains($0.threadID) && !matchedIDs.contains($0.id)
        }
        return MessageListVisibleHeaders.headers(
            from: headers + replies,
            groupByThread: false,
            pinnedIDs: pinnedIDs
        )
    }
}
