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
import Foundation

struct UnifiedInboxPageCursor: Equatable, Sendable {
    let sourceID: MailSourceID
    let inbox: Folder
    let sourceTitle: String
    let sourceSubtitle: String
    let archiveFolder: Folder?
    var nextPageToken: String

    init?(
        section: MailSourceSection,
        inbox: Folder,
        nextPageToken: String?
    ) {
        guard let nextPageToken else { return nil }
        sourceID = section.id
        self.inbox = inbox
        sourceTitle = section.title
        sourceSubtitle = section.subtitle
        archiveFolder = section.folders.first { $0.role == .archive }
        self.nextPageToken = nextPageToken
    }

    func advanced(to nextPageToken: String) -> UnifiedInboxPageCursor {
        var cursor = self
        cursor.nextPageToken = nextPageToken
        return cursor
    }

    func items(from headers: [MessageHeader]) -> [UnifiedInboxItem] {
        headers.map {
            UnifiedInboxItem(
                sourceID: sourceID,
                folder: inbox,
                header: $0,
                sourceTitle: sourceTitle,
                sourceSubtitle: sourceSubtitle,
                archiveFolder: archiveFolder
            )
        }
    }
}

enum UnifiedInboxPagination {
    static func sortedItems(_ items: [UnifiedInboxItem]) -> [UnifiedInboxItem] {
        items.sorted { $0.header.date > $1.header.date }
    }

    static func appendUniquePage(
        _ pageItems: [UnifiedInboxItem],
        to existingItems: [UnifiedInboxItem]
    ) -> [UnifiedInboxItem] {
        var seenIDs = Set(existingItems.map(\.id))
        var merged = existingItems
        for item in pageItems where seenIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return sortedItems(merged)
    }

    static func shouldLoadMore(
        visibleIndex: Int,
        visibleCount: Int,
        hasMore: Bool,
        isLoadingMore: Bool,
        searchText: String
    ) -> Bool {
        guard hasMore,
              !isLoadingMore,
              searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              visibleIndex >= 0,
              visibleIndex < visibleCount
        else {
            return false
        }
        return visibleIndex >= visibleCount - 8
    }
}
