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

/// Reuses the unified presentation projection when navigation reconciliation
/// and SwiftUI body evaluation observe the same inputs in one update. The
/// item array is matched by buffer identity — comparing it element-by-element
/// cost O(n) on every body evaluation even when nothing changed.
final class UnifiedInboxPresentationSnapshotCache {
    struct Key: Equatable {
        let pinnedMessageIDsRaw: String
        let groupByDate: Bool
        let collapsedDateSectionIDs: Set<MessageListDateSection.ID>
        let groupByThread: Bool
        let activeInboxCategory: InboxCategory
        let inboxClassificationModeRaw: String
        let workflowVisibilityMode: LocalMessageWorkflowVisibilityMode
        let workflowState: LocalMessageWorkflowState
        let mailboxFilter: MailboxFilterQuery
        var savedSearchText = ""
        let savedSearchQuery: SmartMailbox.SavedQuery?
        let mailboxSortOrder: MailboxSortOrder
        let temporalInvalidationKey: MailboxListTemporalInvalidationKey
        let calendarDay: Date
        let calendarIdentifier: Calendar.Identifier
        let calendarTimeZoneIdentifier: String
        let localeIdentifier: String
    }

    private var key: Key?
    /// Retained so the buffer-identity check stays sound: a stored array's
    /// backing storage cannot be freed and reallocated while we hold it.
    private var items: [UnifiedInboxItem]?
    private var value: UnifiedInboxPresentationSnapshot?

    func snapshot(
        for key: Key,
        items: [UnifiedInboxItem],
        build: () -> UnifiedInboxPresentationSnapshot
    ) -> UnifiedInboxPresentationSnapshot {
        if self.key == key, let storedItems = self.items,
           items.sharesRetainedBuffer(with: storedItems), let value {
            return value
        }
        let value = build()
        self.key = key
        self.items = items
        self.value = value
        return value
    }
}

struct UnifiedInboxDateSection: Identifiable, Equatable {
    let title: String
    let totalCount: Int
    let isCollapsed: Bool
    let visibleItems: [UnifiedInboxItem]

    var id: String { title }
}

struct UnifiedInboxPresentationSnapshot {
    let visibleItems: [UnifiedInboxItem]
    let dateSections: [UnifiedInboxDateSection]
    let pinnedMessageIDs: Set<MessageHeader.ID>
    /// Messages per thread, keyed by `UnifiedInboxThreadGrouping.key(for:)`.
    /// Empty when thread grouping is off.
    let threadCounts: [String: Int]
    /// Unread/pinned tallies over the *source* item list, not the visible
    /// projection. The folder-stats footer reads them every body evaluation;
    /// deriving them here keeps that O(n) pass inside the cached build.
    let unreadItemCount: Int
    let pinnedItemCount: Int
    /// All source items grouped by `UnifiedInboxThreadGrouping.key(for:)`,
    /// each bucket sorted oldest → newest. An expanded row reads its children
    /// from the bucket in O(thread size) instead of filtering every item.
    let itemsByThreadKey: [String: [UnifiedInboxItem]]

    private let visibleIndexesByItemID: [UnifiedInboxItem.ID: Int]

    init(
        visibleItems: [UnifiedInboxItem],
        pinnedMessageIDsRaw: String,
        groupByDate: Bool,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        threadCounts: [String: Int] = [:],
        sourceItems: [UnifiedInboxItem]? = nil
    ) {
        self.init(
            visibleItems: visibleItems,
            pinnedMessageIDs: Self.pinnedMessageIDs(from: pinnedMessageIDsRaw),
            groupByDate: groupByDate,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            referenceDate: referenceDate,
            calendar: calendar,
            threadCounts: threadCounts,
            sourceItems: sourceItems
        )
    }

    init(
        visibleItems: [UnifiedInboxItem],
        pinnedMessageIDs: Set<MessageHeader.ID>,
        groupByDate: Bool,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        threadCounts: [String: Int] = [:],
        sourceItems: [UnifiedInboxItem]? = nil
    ) {
        self.visibleItems = visibleItems
        self.pinnedMessageIDs = pinnedMessageIDs
        self.threadCounts = threadCounts
        let sourceItems = sourceItems ?? visibleItems
        unreadItemCount = sourceItems.reduce(into: 0) { count, item in
            count += item.header.isRead ? 0 : 1
        }
        pinnedItemCount = sourceItems.reduce(into: 0) { count, item in
            count += pinnedMessageIDs.contains(item.pinID) ? 1 : 0
        }
        itemsByThreadKey = Dictionary(
            grouping: sourceItems,
            by: UnifiedInboxThreadGrouping.key(for:)
        ).mapValues { $0.sorted { $0.header.date < $1.header.date } }
        visibleIndexesByItemID = Dictionary(
            uniqueKeysWithValues: visibleItems.enumerated().map { ($0.element.id, $0.offset) }
        )
        dateSections = groupByDate
            ? Self.makeDateSections(
                items: visibleItems,
                pinnedMessageIDs: pinnedMessageIDs,
                collapsedDateSectionIDs: collapsedDateSectionIDs,
                referenceDate: referenceDate,
                calendar: calendar
            )
            : []
    }

    static func pinnedMessageIDs(from rawValue: String) -> Set<MessageHeader.ID> {
        Set(rawValue.split(separator: "\n").map(String.init))
    }

    func visibleIndex(for itemID: UnifiedInboxItem.ID) -> Int? {
        visibleIndexesByItemID[itemID]
    }

    private static func makeDateSections(
        items: [UnifiedInboxItem],
        pinnedMessageIDs: Set<MessageHeader.ID>,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date,
        calendar: Calendar
    ) -> [UnifiedInboxDateSection] {
        var groupedItems: [(title: String, items: [UnifiedInboxItem])] = []
        let pinnedItems = items.filter { pinnedMessageIDs.contains($0.pinID) }
        if !pinnedItems.isEmpty {
            groupedItems.append((title: "Pinned", items: pinnedItems))
        }

        var currentTitle: String?
        var currentItems: [UnifiedInboxItem] = []
        for item in items where !pinnedMessageIDs.contains(item.pinID) {
            let title = MessageListDateGrouping.sectionTitle(
                for: item.header.date,
                referenceDate: referenceDate,
                calendar: calendar
            )
            if currentTitle == title {
                currentItems.append(item)
            } else {
                appendGroup(title: currentTitle, items: currentItems, to: &groupedItems)
                currentTitle = title
                currentItems = [item]
            }
        }
        appendGroup(title: currentTitle, items: currentItems, to: &groupedItems)

        return groupedItems.map { group in
            let isCollapsed = collapsedDateSectionIDs.contains(group.title)
            return UnifiedInboxDateSection(
                title: group.title,
                totalCount: group.items.count,
                isCollapsed: isCollapsed,
                visibleItems: isCollapsed ? [] : group.items
            )
        }
    }

    private static func appendGroup(
        title: String?,
        items: [UnifiedInboxItem],
        to groups: inout [(title: String, items: [UnifiedInboxItem])]
    ) {
        guard let title, !items.isEmpty else { return }
        groups.append((title: title, items: items))
    }
}
