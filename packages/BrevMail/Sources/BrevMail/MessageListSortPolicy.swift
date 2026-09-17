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
import Foundation

enum MessageListSortPolicy {
    static func sorted(
        _ headers: [MessageHeader],
        by order: MailboxSortOrder,
        pinnedIDs: Set<MessageHeader.ID>
    ) -> [MessageHeader] {
        let unpinned = headers.filter { !pinnedIDs.contains($0.id) }
        let pinned = headers.filter { pinnedIDs.contains($0.id) }

        let sortedPinned = sortHeaders(pinned, by: order)
        let sorted = sortHeaders(unpinned, by: order)
        return sortedPinned + sorted
    }

    static func sortedItems(
        _ items: [UnifiedInboxItem],
        by order: MailboxSortOrder,
        pinnedIDs: Set<MessageHeader.ID>
    ) -> [UnifiedInboxItem] {
        let unpinned = items.filter { !pinnedIDs.contains($0.pinID) }
        let pinned = items.filter { pinnedIDs.contains($0.pinID) }

        let sortedPinned = pinned.sorted {
            areHeadersInSortOrder($0.header, $1.header, order: order)
        }
        let sorted = unpinned.sorted {
            areHeadersInSortOrder($0.header, $1.header, order: order)
        }
        return sortedPinned + sorted
    }

    static func filtered(
        _ headers: [MessageHeader],
        by filter: MailboxFilterQuery,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MessageHeader] {
        headers.filter { filter.matches($0, now: now, calendar: calendar) }
    }

    private static func sortHeaders(
        _ headers: [MessageHeader],
        by order: MailboxSortOrder
    ) -> [MessageHeader] {
        switch order {
        case .newestFirst:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .oldestFirst:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .sender:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .subject:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .unreadFirst:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .flaggedFirst:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        case .attachmentFirst:
            return headers.sorted { areHeadersInSortOrder($0, $1, order: order) }
        }
    }

    private static func areHeadersInSortOrder(
        _ lhs: MessageHeader,
        _ rhs: MessageHeader,
        order: MailboxSortOrder
    ) -> Bool {
        switch order {
        case .newestFirst:
            return newestThenID(lhs, rhs)
        case .oldestFirst:
            return oldestThenID(lhs, rhs)
        case .sender:
            let displayNameOrder = lhs.from.displayName.localizedCaseInsensitiveCompare(rhs.from.displayName)
            if displayNameOrder != .orderedSame {
                return displayNameOrder == .orderedAscending
            }
            let emailOrder = lhs.from.email.localizedCaseInsensitiveCompare(rhs.from.email)
            if emailOrder != .orderedSame {
                return emailOrder == .orderedAscending
            }
            return newestThenID(lhs, rhs)
        case .subject:
            let subjectOrder = lhs.subject.localizedCaseInsensitiveCompare(rhs.subject)
            if subjectOrder != .orderedSame {
                return subjectOrder == .orderedAscending
            }
            return newestThenID(lhs, rhs)
        case .unreadFirst:
            if lhs.isRead != rhs.isRead { return !lhs.isRead }
            return newestThenID(lhs, rhs)
        case .flaggedFirst:
            if lhs.isFlagged != rhs.isFlagged { return lhs.isFlagged }
            return newestThenID(lhs, rhs)
        case .attachmentFirst:
            if lhs.hasAttachments != rhs.hasAttachments { return lhs.hasAttachments }
            return newestThenID(lhs, rhs)
        }
    }

    private static func newestThenID(_ lhs: MessageHeader, _ rhs: MessageHeader) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }

    private static func oldestThenID(_ lhs: MessageHeader, _ rhs: MessageHeader) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}
