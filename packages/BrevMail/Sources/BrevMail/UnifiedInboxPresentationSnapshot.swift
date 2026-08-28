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
/// and SwiftUI body evaluation observe the same inputs in one update.
final class UnifiedInboxPresentationSnapshotCache {
    struct Key: Equatable {
        let items: [UnifiedInboxItem]
        let pinnedMessageIDsRaw: String
        let groupByDate: Bool
        let collapsedDateSectionIDs: Set<MessageListDateSection.ID>
        let groupByThread: Bool
        let activeInboxCategory: InboxCategory
        let inboxClassificationModeRaw: String
        let workflowVisibilityMode: LocalMessageWorkflowVisibilityMode
        let workflowState: LocalMessageWorkflowState
        let mailboxFilter: MailboxFilterQuery
        let savedSearchQuery: SearchQuery?
        let mailboxSortOrder: MailboxSortOrder
        let temporalInvalidationKey: MailboxListTemporalInvalidationKey
        let calendarDay: Date
        let calendarIdentifier: Calendar.Identifier
        let calendarTimeZoneIdentifier: String
        let localeIdentifier: String
    }

    private var key: Key?
    private var value: UnifiedInboxPresentationSnapshot?

    func snapshot(
        for key: Key,
        build: () -> UnifiedInboxPresentationSnapshot
    ) -> UnifiedInboxPresentationSnapshot {
        if self.key == key, let value {
            return value
        }
        let value = build()
        self.key = key
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

    private let visibleIndexesByItemID: [UnifiedInboxItem.ID: Int]

    init(
        visibleItems: [UnifiedInboxItem],
        pinnedMessageIDsRaw: String,
        groupByDate: Bool,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        threadCounts: [String: Int] = [:]
    ) {
        self.init(
            visibleItems: visibleItems,
            pinnedMessageIDs: Self.pinnedMessageIDs(from: pinnedMessageIDsRaw),
            groupByDate: groupByDate,
            collapsedDateSectionIDs: collapsedDateSectionIDs,
            referenceDate: referenceDate,
            calendar: calendar,
            threadCounts: threadCounts
        )
    }

    init(
        visibleItems: [UnifiedInboxItem],
        pinnedMessageIDs: Set<MessageHeader.ID>,
        groupByDate: Bool,
        collapsedDateSectionIDs: Set<MessageListDateSection.ID>,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        threadCounts: [String: Int] = [:]
    ) {
        self.visibleItems = visibleItems
        self.pinnedMessageIDs = pinnedMessageIDs
        self.threadCounts = threadCounts
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
        let pinnedItems = items.filter { pinnedMessageIDs.contains($0.header.id) }
        if !pinnedItems.isEmpty {
            groupedItems.append((title: "Pinned", items: pinnedItems))
        }

        var currentTitle: String?
        var currentItems: [UnifiedInboxItem] = []
        for item in items where !pinnedMessageIDs.contains(item.header.id) {
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

/// Keeps the local pinned-message preference bounded without pruning IDs that
/// may simply belong to a later page of a partial unified-inbox load.
enum UnifiedInboxPinnedMessagePersistence {
    static let maximumPersistedCount = 500

    static func reconciledIDs(
        stored: Set<MessageHeader.ID>,
        loaded: Set<MessageHeader.ID>,
        isComplete: Bool
    ) -> Set<MessageHeader.ID> {
        let candidates = isComplete ? stored.intersection(loaded) : stored
        return Set(candidates.sorted().prefix(maximumPersistedCount))
    }
}
