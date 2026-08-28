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

import Foundation

/// File-backed persistent cache for raw IMAP message sources.
///
/// Each message is stored as a JSON file named by a hex-encoded message ID
/// under `Application Support/Brev/Cache/<accountKey>/`.  The cache is capped
/// at 50 MiB per account; when the limit is exceeded, the oldest files are
/// evicted until the account directory fits within the budget.
///
/// Falls back to nil on any I/O error so cache misses are transparent to
/// callers.  This type is a convenience wrapper around `FileIMAPMessageSourceCache`
/// that supplies the standard application storage directory and the default
/// 50 MiB eviction cap.
public actor FileBackedIMAPMessageSourceCache: IMAPMessageSourceCache {
    /// 50 MiB per-account storage cap.
    public static let defaultMaximumAccountSizeBytes = 50 * 1024 * 1024

    private let inner: FileIMAPMessageSourceCache

    /// Creates a cache in `Application Support/Brev/Cache` with a 50 MiB cap.
    public init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        inner = FileIMAPMessageSourceCache(
            rootDirectory: base,
            maximumAccountSizeBytes: FileBackedIMAPMessageSourceCache.defaultMaximumAccountSizeBytes
        )
    }

    /// Creates a cache rooted at an arbitrary directory — used by tests.
    public init(rootDirectory: URL, maximumAccountSizeBytes: Int? = nil) {
        inner = FileIMAPMessageSourceCache(
            rootDirectory: rootDirectory,
            maximumAccountSizeBytes: maximumAccountSizeBytes
        )
    }

    public func source(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) async -> IMAPMessageSource? {
        await inner.source(accountID: accountID, messageID: messageID)
    }

    public func setSource(
        _ source: IMAPMessageSource,
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) async {
        await inner.setSource(source, accountID: accountID, messageID: messageID)
    }

    public func removeSource(
        accountID: BrevAccount.ID,
        messageID: MessageHeader.ID
    ) async {
        await inner.removeSource(accountID: accountID, messageID: messageID)
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID
    ) async {
        await inner.removeSources(inFolder: folderID, accountID: accountID)
    }

    public func removeSources(
        inFolder folderID: Folder.ID,
        accountID: BrevAccount.ID,
        exceptMessageIDs: Set<MessageHeader.ID>
    ) async {
        await inner.removeSources(inFolder: folderID, accountID: accountID, exceptMessageIDs: exceptMessageIDs)
    }

    public nonisolated func sizeBytes(accountID: BrevAccount.ID) async -> Int {
        inner.sizeBytes(accountID: accountID)
    }

    public func clear(accountID: BrevAccount.ID) async {
        await inner.clear(accountID: accountID)
    }
}
