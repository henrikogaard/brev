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

enum CachedPDFClause {
    static let pattern = #"(?<!\S)(?:(?:with|has|med|har)\s+(?:(?:a|en)\s+)?)?pdf(?:s|-vedlegg)?(?=\s|$)"#
    static var title: String { String(localized: "Has: PDF (cached)", bundle: .module) }
}

/// File type is proven by cached attachment metadata, independently of the header's attachment hint.
enum CachedPDFSearch {
    enum SearchError: LocalizedError {
        case requiresLocalSearch

        var errorDescription: String? {
            String(localized: "PDF search uses downloaded mail. Choose an on-device search.", bundle: .module)
        }
    }

    static func headers(backend: any MailBackend, query: SearchQuery, folders: [Folder],
                        sourceID: MailSourceID?) async throws -> [MessageHeader] {
        guard query.execution != .serverOnly else { throw SearchError.requiresLocalSearch }
        try Task.checkCancellation()
        let selected = folders.filter { query.folderScope?.contains($0.id) ?? true }
        let messages: [CachedAttachmentMessage]
        if let sourceID {
            messages = await backend.cachedAttachmentMessages(in: selected, sourceID: sourceID)
        } else {
            messages = await backend.cachedAttachmentMessages(in: selected)
        }
        try Task.checkCancellation()
        guard !messages.isEmpty, !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return matches(messages, query: query)
        }
        // Only the backend's existing cache search knows which body, filename, or indexed content matched.
        var lookup = query
        lookup.execution = .cacheOnly
        if lookup.hasAttachments == true { lookup.hasAttachments = nil }
        let indexed: [MessageHeader]
        if let sourceID {
            indexed = try await backend.search(lookup, sourceID: sourceID)
        } else {
            indexed = try await backend.search(lookup)
        }
        try Task.checkCancellation()
        let ids = Set(indexed.map(\.id))
        lookup.text = ""
        return matches(messages.filter { ids.contains($0.header.id) }, query: lookup)
    }

    static func matches(_ messages: [CachedAttachmentMessage], query: SearchQuery) -> [MessageHeader] {
        var remaining = query
        if remaining.hasAttachments == true { remaining.hasAttachments = nil }
        var seen: Set<MessageHeader.ID> = []
        return messages.compactMap { message in
            guard remaining.matches(message.header),
                  message.body.attachments.contains(where: { !$0.isInline && AttachmentSearchFileType.pdf.matches($0) }),
                  seen.insert(message.header.id).inserted else { return nil }
            return message.header
        }.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }
}
