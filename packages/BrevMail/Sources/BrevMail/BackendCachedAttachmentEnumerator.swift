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

/// Production `CachedAttachmentEnumerating` for the All Attachments surface.
///
/// For each visible source it asks the owning `MailBackend` for the messages
/// it has already cached with attachments (`cachedAttachmentMessages`, a
/// read-only, cache-only seam — ADR-0044) and maps them to
/// `CachedAttachmentSource` values, tagging each with its source identity and
/// folder name. It never triggers a download or network call.
struct BackendCachedAttachmentEnumerator: CachedAttachmentEnumerating {
    let backends: [any MailBackend]
    let sourceSections: [MailSourceSection]

    func cachedMessagesWithBodies() async -> [CachedAttachmentSource] {
        var results: [CachedAttachmentSource] = []
        for section in sourceSections {
            guard let backend = backends.first(where: { $0.account.id == section.account.id }) else {
                continue
            }
            let messages = await backend.cachedAttachmentMessages(
                in: section.folders,
                sourceID: section.id
            )
            for message in messages {
                results.append(
                    CachedAttachmentSource(
                        sourceID: section.id,
                        sourceName: section.mailbox.displayName,
                        folderName: message.folder.name,
                        header: message.header,
                        body: message.body
                    )
                )
            }
        }
        return results
    }
}
