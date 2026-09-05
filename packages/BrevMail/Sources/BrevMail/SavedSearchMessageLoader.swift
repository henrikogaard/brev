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
import BrevSettings

/// Saved views enumerate cached folders instead of silently searching only Inbox.
enum SavedSearchMessageLoader {
    static func load(section: MailSourceSection, backend: any MailBackend,
                     query: SmartMailbox.SavedQuery) async throws -> [UnifiedInboxItem] {
        var items: [UnifiedInboxItem] = []
        for folder in section.folders {
            try Task.checkCancellation()
            if query.includeTrash == false, folder.role == .trash { continue }
            if query.includeSent == false, folder.role == .sent { continue }
            let headers = try await backend.search(
                SearchQuery(folderID: folder.id, execution: .cacheOnly), sourceID: section.id
            )
            items.append(contentsOf: headers.map {
                UnifiedInboxItem(sourceID: section.id, folder: folder, header: $0,
                                 sourceTitle: section.title, sourceSubtitle: section.subtitle,
                                 archiveFolder: section.folders.first { $0.role == .archive })
            })
        }
        // Label providers can expose the same message in several folders. Keep
        // one row, preferring the membership that satisfies a folder condition.
        var indexes: [MessageHeader.ID: Int] = [:]
        var unique: [UnifiedInboxItem] = []
        for item in items {
            if let index = indexes[item.header.id] {
                let previous = unique[index]
                if query.matches(item.header, sourceID: item.sourceID, folderRole: item.folder.role),
                   !query.matches(previous.header, sourceID: previous.sourceID, folderRole: previous.folder.role) {
                    unique[index] = item
                }
            } else {
                indexes[item.header.id] = unique.count
                unique.append(item)
            }
        }
        return unique
    }
}
