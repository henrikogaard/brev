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

/// A single already-cached message with its body, used to derive attachment records.
struct CachedAttachmentSource: Sendable {
    let sourceID: MailSourceID
    let sourceName: String
    let folderName: String
    let header: MessageHeader
    let body: MessageBody
}

/// Read-only enumeration of cached messages that have a cached body.
/// Implementations MUST NOT trigger downloads or network (ADR-0041).
protocol CachedAttachmentEnumerating: Sendable {
    func cachedMessagesWithBodies() async -> [CachedAttachmentSource]
}

/// Derives `[AttachmentSearchRecord]` from cached message bodies, excluding inline parts.
struct CachedAttachmentSearchRecordProvider: AttachmentSearchRecordProviding {
    let enumerator: any CachedAttachmentEnumerating
    /// Optional local-index lookup for attachment *content* matches (ADR-0078).
    /// Must be cache-only; nil leaves the filter metadata-only.
    let contentMatcher: (@Sendable (String, [MessageHeader.ID]) async -> [MessageHeader.ID: String])?

    init(
        enumerator: any CachedAttachmentEnumerating,
        contentMatcher: (@Sendable (String, [MessageHeader.ID]) async -> [MessageHeader.ID: String])? = nil
    ) {
        self.enumerator = enumerator
        self.contentMatcher = contentMatcher
    }

    func attachmentContentMatchedMessageIDs(
        query: String,
        candidateMessageIDs: [MessageHeader.ID]
    ) async -> Set<MessageHeader.ID> {
        guard let contentMatcher, !query.isEmpty else { return [] }
        return await Set(contentMatcher(query, candidateMessageIDs).keys)
    }

    func attachmentRecords() async -> [AttachmentSearchRecord] {
        let cached = await enumerator.cachedMessagesWithBodies()
        return cached.flatMap { item in
            item.body.attachments
                .filter { !$0.isInline }
                .map { attachment in
                    AttachmentSearchRecord(
                        sourceID: item.sourceID,
                        sourceName: item.sourceName,
                        header: item.header,
                        folderName: item.folderName,
                        attachment: attachment,
                        bodyCacheState: .cached,
                        contentIndexState: .notIndexed
                    )
                }
        }
    }
}
