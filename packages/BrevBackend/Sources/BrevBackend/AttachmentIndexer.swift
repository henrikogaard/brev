/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions of the LICENSE file.
 */

import Foundation

/// Local-only indexer for attachment text already present on device
/// (ADR-0078). Owned by one backend/account; consults the per-account
/// consent provider before every unit of work and stops immediately when it
/// turns off.
///
/// The indexer is strictly cache-only: `rawMessageProvider` must return
/// `nil` rather than fetch when a source is not already cached, and the
/// indexing path never calls `downloadAttachment`. One message is processed
/// at a time; each attachment extraction runs in a detached utility task
/// under `AttachmentTextExtractor`'s 10-second timeout.
public actor AttachmentIndexer {
    /// One unit of sweep work: a cached message and the folder it lives in.
    public struct SweepEntry: Sendable, Hashable {
        public let messageID: MessageHeader.ID
        public let folderID: Folder.ID
        public init(messageID: MessageHeader.ID, folderID: Folder.ID) {
            self.messageID = messageID
            self.folderID = folderID
        }
    }

    private let accountID: String
    private let isEnabled: @Sendable () -> Bool
    private let index: any MailLocalSearchIndex
    /// Enumerates cached messages eligible for indexing (already-filtered to
    /// `hasAttachments` where the caller can know that cheaply).
    private let sweepEntries: @Sendable () async -> [SweepEntry]
    /// Reads the already-cached raw RFC 5322 message. Must be cache-only —
    /// returning `nil` instead of fetching.
    private let rawMessageProvider: @Sendable (MessageHeader.ID) async -> String?

    private var pending: [SweepEntry] = []
    private var queued = Set<MessageHeader.ID>()
    private var processing = false
    /// Bumped on `stop()`/`disable()` so an in-flight drain exits early.
    private var generation = 0

    public init(
        accountID: String,
        isEnabled: @escaping @Sendable () -> Bool,
        index: any MailLocalSearchIndex,
        sweepEntries: @escaping @Sendable () async -> [SweepEntry],
        rawMessageProvider: @escaping @Sendable (MessageHeader.ID) async -> String?
    ) {
        self.accountID = accountID
        self.isEnabled = isEnabled
        self.index = index
        self.sweepEntries = sweepEntries
        self.rawMessageProvider = rawMessageProvider
    }

    /// Enqueues a message whose source was just cached (ADR-0078 §2).
    public func noteSourceCached(messageID: MessageHeader.ID, folderID: Folder.ID) {
        guard isEnabled(), queued.insert(messageID).inserted else { return }
        pending.append(SweepEntry(messageID: messageID, folderID: folderID))
        kick()
    }

    /// Low-priority pass over every cached message not yet indexed. Called at
    /// connect time by the owning backend.
    public func sweep() async {
        guard isEnabled() else { return }
        let already = await index.indexedAttachmentMessageIDs(accountID: accountID)
        for entry in await sweepEntries() where !already.contains(entry.messageID) {
            guard queued.insert(entry.messageID).inserted else { continue }
            pending.append(entry)
        }
        kick()
    }

    /// Removes all indexed rows for the account and repopulates from the
    /// current cache. Used by the Mail Storage "Rebuild" action.
    public func rebuild() async {
        stop()
        try? await index.removeAllAttachmentText(accountID: accountID)
        await sweep()
    }

    /// Stops queued and in-flight work (disconnect / flushLocalCaches).
    public func stop() {
        generation += 1
        pending.removeAll()
        queued.removeAll()
    }

    /// Consent revocation: stop work and delete every indexed row so the
    /// toggle being off means no attachment text remains (ADR-0078 §1).
    public func disable() async {
        stop()
        try? await index.removeAllAttachmentText(accountID: accountID)
    }

    // MARK: - Processing

    private func kick() {
        guard !processing, isEnabled() else { return }
        processing = true
        let generation = generation
        Task(priority: .utility) { [weak self] in
            await self?.drain(generation: generation)
        }
    }

    private func drain(generation expected: Int) async {
        defer { processing = false }
        while !pending.isEmpty {
            guard generation == expected, isEnabled(), !Task.isCancelled else { return }
            let entry = pending.removeFirst()
            queued.remove(entry.messageID)
            await process(entry, generation: expected)
        }
    }

    private func process(_ entry: SweepEntry, generation expected: Int) async {
        let startedAt = Date()
        var indexedCount = 0
        var indexedBytes = 0
        defer {
            MailPerformanceDiagnostics.logAttachmentIndex(
                count: indexedCount,
                bytes: indexedBytes,
                durationMs: MailPerformanceDiagnostics.durationMilliseconds(since: startedAt)
            )
        }
        guard isEnabled(), !Task.isCancelled,
              let rawMessage = await rawMessageProvider(entry.messageID)
        else { return }
        guard generation == expected else { return }

        let parser = IMAPMessageBodyParser()
        let parsed = parser.parse(messageID: entry.messageID, rawMessage: rawMessage)
        for (offset, attachment) in parsed.attachments.enumerated() {
            guard !attachment.isInline else { continue }
            guard isEnabled(), generation == expected, !Task.isCancelled else { return }
            guard attachment.sizeBytes <= AttachmentTextExtractor.maxInputBytes else { continue }
            guard let data = parser.attachmentData(
                attachmentIndex: offset + 1,
                rawMessage: rawMessage
            ) else { continue }
            let mimeType = attachment.mimeType
            let name = attachment.name
            let text = try? await Task.detached(priority: .utility) {
                try await AttachmentTextExtractor.extract(
                    data: data,
                    mimeType: mimeType,
                    fileName: name,
                    timeout: AttachmentTextExtractor.defaultTimeout
                )
            }.value
            guard let text, !text.isEmpty else { continue }
            guard isEnabled(), generation == expected else { return }
            try? await index.indexAttachmentText(
                accountID: accountID,
                messageID: entry.messageID,
                folderID: entry.folderID,
                attachmentID: attachment.id,
                name: name,
                text: text
            )
            indexedCount += 1
            indexedBytes += text.utf8.count
        }
    }
}
