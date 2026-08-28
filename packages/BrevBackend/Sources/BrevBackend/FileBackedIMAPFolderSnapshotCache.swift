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

/// File-backed persistent cache for IMAP folder list snapshots.
///
/// Each account's snapshot is stored as a single JSON file at
/// `Application Support/Brev/Cache/<accountKey>/folders.json`.
/// An in-memory write-through layer avoids redundant disk I/O within a
/// session. Falls back to nil on any I/O error so cache misses are
/// transparent to callers.
public actor FileBackedIMAPFolderSnapshotCache: IMAPFolderSnapshotCache {
    private let rootDirectory: URL
    private var memoryCache: [BrevAccount.ID: IMAPFolderCacheSnapshot] = [:]

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

    public func snapshot(accountID: BrevAccount.ID) -> IMAPFolderCacheSnapshot? {
        if let cached = memoryCache[accountID] {
            return cached
        }
        let url = snapshotURL(accountID: accountID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(IMAPFolderCacheSnapshot.self, from: data)
        else {
            return nil
        }
        memoryCache[accountID] = decoded
        return decoded
    }

    public func setSnapshot(_ snapshot: IMAPFolderCacheSnapshot, accountID: BrevAccount.ID) {
        memoryCache[accountID] = snapshot

        let directory = accountDirectory(accountID: accountID)
        let url = snapshotURL(accountID: accountID)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache write failures are non-fatal.
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        memoryCache.removeValue(forKey: accountID)
        let directory = accountDirectory(accountID: accountID)
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Private helpers

    private func accountDirectory(accountID: BrevAccount.ID) -> URL {
        rootDirectory.appendingPathComponent(Self.fileKey(accountID), isDirectory: true)
    }

    private func snapshotURL(accountID: BrevAccount.ID) -> URL {
        accountDirectory(accountID: accountID)
            .appendingPathComponent("folders.json", isDirectory: false)
    }

    /// Hex-encodes a string so it is safe to use as a file/directory name.
    private static func fileKey(_ value: String) -> String {
        guard !value.isEmpty else { return "_" }
        return value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
