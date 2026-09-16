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

/// File-backed persistent cache for IMAP mailbox header snapshots.
///
/// Snapshots are stored as JSON files under
/// `Application Support/Brev/Cache/<accountKey>/headers/<folderKey>.json`.
/// An in-memory write-through layer avoids redundant disk I/O within a
/// session. Falls back to nil on any I/O error so cache misses are
/// transparent to callers.
///
/// Disk writes are coalesced: `setSnapshot` updates memory immediately and
/// marks the folder dirty, and a short debounce flushes all dirty folders in
/// one pass. Every mutation used to re-encode and atomically rewrite the
/// whole folder JSON, so a page fetch, a flag update, and a CONDSTORE delta
/// each paid a full-folder write. Unflushed changes are lost on process
/// termination — acceptable for a cache that the server can rebuild.
public actor FileBackedIMAPMailboxHeaderCache: IMAPMailboxHeaderCache {
    private struct DirtyFolder: Hashable {
        let accountID: BrevAccount.ID
        let folderID: Folder.ID
    }

    private let rootDirectory: URL
    private var memoryCache: [BrevAccount.ID: [Folder.ID: IMAPMailboxHeaderCacheSnapshot]] = [:]
    private var dirtyFolders: Set<DirtyFolder> = []
    private var flushTask: Task<Void, Never>?
    private static let flushDelay = Duration.milliseconds(750)

    /// Creates a cache rooted at `Application Support/Brev/Cache`.
    public init() {
        rootDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// Creates a cache rooted at an arbitrary directory — used by tests.
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func snapshot(
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) -> IMAPMailboxHeaderCacheSnapshot? {
        if let cached = memoryCache[accountID]?[folderID] {
            return cached
        }
        let url = snapshotURL(accountID: accountID, folderID: folderID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  IMAPMailboxHeaderCacheSnapshot.self,
                  from: data
              )
        else {
            return nil
        }
        var folders = memoryCache[accountID] ?? [:]
        folders[folderID] = decoded
        memoryCache[accountID] = folders
        return decoded
    }

    public func setSnapshot(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) {
        var folders = memoryCache[accountID] ?? [:]
        folders[folderID] = snapshot
        memoryCache[accountID] = folders

        dirtyFolders.insert(DirtyFolder(accountID: accountID, folderID: folderID))
        scheduleFlush()
    }

    /// Writes every dirty in-memory snapshot to disk. Called by the debounce
    /// timer; also exposed so lifecycle hooks and tests can force durability.
    /// Declared `async` so `await cache.flushPendingWrites()` picks this
    /// member over the protocol's default no-op in async contexts.
    public func flushPendingWrites() async {
        flushTask = nil
        let pending = dirtyFolders
        dirtyFolders.removeAll()
        guard !pending.isEmpty else { return }

        let interval = MailPerformanceDiagnostics.beginInterval("IMAP Header Cache Flush")
        var totalBytes = 0
        for entry in pending {
            guard let snapshot = memoryCache[entry.accountID]?[entry.folderID] else { continue }
            totalBytes += write(snapshot, accountID: entry.accountID, folderID: entry.folderID)
        }
        MailPerformanceDiagnostics.endInterval(interval)
        MailPerformanceDiagnostics.logHeaderCacheFlush(
            folderCount: pending.count,
            totalBytes: totalBytes,
            durationMilliseconds: MailPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
        )
    }

    public func clear(accountID: BrevAccount.ID) {
        memoryCache.removeValue(forKey: accountID)
        dirtyFolders = dirtyFolders.filter { $0.accountID != accountID }
        // Remove the entire account directory (which contains the headers/ subdirectory).
        let directory = rootDirectory.appendingPathComponent(
            Self.fileKey(accountID),
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: directory)
    }

    public func clear(accountID: BrevAccount.ID, folderID: Folder.ID) {
        memoryCache[accountID]?.removeValue(forKey: folderID)
        if memoryCache[accountID]?.isEmpty == true {
            memoryCache.removeValue(forKey: accountID)
        }
        dirtyFolders.remove(DirtyFolder(accountID: accountID, folderID: folderID))
        try? FileManager.default.removeItem(at: snapshotURL(accountID: accountID, folderID: folderID))
    }

    // MARK: Private helpers

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            await self?.flushPendingWrites()
        }
    }

    /// Encodes and atomically writes one folder snapshot. Returns the encoded
    /// byte count for diagnostics; zero on failure.
    @discardableResult
    private func write(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) -> Int {
        let directory = accountDirectory(accountID: accountID)
        let url = snapshotURL(accountID: accountID, folderID: folderID)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return data.count
        } catch {
            // Cache write failures are non-fatal.
            return 0
        }
    }

    private func accountDirectory(accountID: BrevAccount.ID) -> URL {
        rootDirectory
            .appendingPathComponent(Self.fileKey(accountID), isDirectory: true)
            .appendingPathComponent("headers", isDirectory: true)
    }

    private func snapshotURL(accountID: BrevAccount.ID, folderID: Folder.ID) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("\(Self.fileKey(folderID)).json", isDirectory: false)
    }

    /// Hex-encodes a string so it is safe to use as a file/directory name.
    private static func fileKey(_ value: String) -> String {
        guard !value.isEmpty else { return "_" }
        return value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
