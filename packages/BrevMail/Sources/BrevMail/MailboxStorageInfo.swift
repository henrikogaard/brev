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

struct MailboxStorageBreakdown: Equatable, Sendable {
    let cacheBytes: Int64
    let cacheObjectCount: Int
    let draftStagingBytes: Int64
    let draftStagingObjectCount: Int
    let offlineMetadataBytes: Int64
    let offlineMetadataObjectCount: Int

    var totalBytes: Int64 {
        cacheBytes + draftStagingBytes + offlineMetadataBytes
    }

    var totalObjectCount: Int {
        cacheObjectCount + draftStagingObjectCount + offlineMetadataObjectCount
    }
}

private struct MailboxStorageDirectoryMetrics: Equatable, Sendable {
    var bytes: Int64 = 0
    var objectCount = 0
}

/// Read-only helpers describing where a mailbox's cached data lives on disk and
/// how much space it uses. Mirrors the layout of the file-backed IMAP caches,
/// which store everything under `Application Support/Brev/Cache/<accountKey>/`.
enum MailboxStorageInfo {
    /// Root of Brev's on-disk mailbox cache.
    static func cacheRoot(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Cache", isDirectory: true)
    }

    /// Cache directory for a specific account. The directory name matches the
    /// hex-encoded key used by the file-backed caches.
    static func accountDirectory(
        accountID: String,
        fileManager: FileManager = .default
    ) -> URL? {
        cacheRoot(fileManager: fileManager)?
            .appendingPathComponent(hexKey(accountID), isDirectory: true)
    }

    /// Root of Brev's on-disk draft staging store (queued drafts and their
    /// attachments). Sits alongside the cache, not under it, so it is
    /// measured separately when totalling an account's footprint.
    static func draftsRoot(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Brev/Drafts", isDirectory: true)
    }

    /// Draft staging directory for a specific account. Same hex-key
    /// derivation as the caches.
    static func draftsDirectory(
        accountID: String,
        fileManager: FileManager = .default
    ) -> URL? {
        draftsRoot(fileManager: fileManager)?
            .appendingPathComponent(hexKey(accountID), isDirectory: true)
    }

    /// Total on-disk footprint, in bytes, of everything Brev caches for one
    /// account: the file-backed message/header/folder caches plus the draft
    /// staging store. This is the honest "how much local data is cached"
    /// number surfaced in the Storage panel.
    static func totalAccountSize(
        accountID: String,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> Int64 {
        storageBreakdown(
            accountID: accountID,
            fileManager: fileManager,
            defaults: defaults
        ).totalBytes
    }

    static func storageBreakdown(
        accountID: String,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) -> MailboxStorageBreakdown {
        var cacheMetrics = MailboxStorageDirectoryMetrics()
        if let cacheURL = accountDirectory(accountID: accountID, fileManager: fileManager) {
            cacheMetrics = directoryMetrics(at: cacheURL, fileManager: fileManager)
            cacheMetrics.objectCount = cacheObjectCount(at: cacheURL, fileManager: fileManager)
        }
        var draftStagingMetrics = MailboxStorageDirectoryMetrics()
        if let draftsURL = draftsDirectory(accountID: accountID, fileManager: fileManager) {
            draftStagingMetrics = directoryMetrics(at: draftsURL, fileManager: fileManager)
        }
        let offlineMetadata = offlineMetadataMetrics(accountID: accountID, defaults: defaults)
        return MailboxStorageBreakdown(
            cacheBytes: cacheMetrics.bytes,
            cacheObjectCount: cacheMetrics.objectCount,
            draftStagingBytes: draftStagingMetrics.bytes,
            draftStagingObjectCount: draftStagingMetrics.objectCount,
            offlineMetadataBytes: offlineMetadata.bytes,
            offlineMetadataObjectCount: offlineMetadata.objectCount
        )
    }

    static func offlineMetadataSize(
        accountID: String,
        defaults: UserDefaults = .standard
    ) -> Int64 {
        offlineMetadataMetrics(accountID: accountID, defaults: defaults).bytes
    }

    private static func offlineMetadataMetrics(
        accountID: String,
        defaults: UserDefaults = .standard
    ) -> MailboxStorageDirectoryMetrics {
        let keys = [
            OfflineMutationQueueStorage.storageKey(accountID: accountID),
            OfflineMutationQueueStorage.conflictStorageKey(accountID: accountID)
        ]
        return keys.reduce(into: MailboxStorageDirectoryMetrics()) { metrics, key in
            guard let data = defaults.data(forKey: key) else { return }
            metrics.bytes += Int64(data.count)
            metrics.objectCount += 1
        }
    }

    /// Lowercase hex encoding of the UTF-8 bytes of `value`, matching the
    /// `fileKey` derivation in the file-backed caches. Delegates to the shared
    /// `MailCacheKeyNaming` so this and the Settings storage panel cannot drift.
    static func hexKey(_ value: String) -> String {
        MailCacheKeyNaming.hexKey(value)
    }

    /// Total on-disk size, in bytes, of all files under `url`. Returns 0 if the
    /// directory does not exist yet.
    static func directorySize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        directoryMetrics(at: url, fileManager: fileManager).bytes
    }

    /// Number of regular files under `url`. Directories are containers, not
    /// cache objects, so they are omitted from the surfaced object count.
    static func directoryObjectCount(at url: URL, fileManager: FileManager = .default) -> Int {
        directoryMetrics(at: url, fileManager: fileManager).objectCount
    }

    private static func directoryMetrics(
        at url: URL,
        fileManager: FileManager = .default
    ) -> MailboxStorageDirectoryMetrics {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return MailboxStorageDirectoryMetrics()
        }
        var metrics = MailboxStorageDirectoryMetrics()
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            metrics.bytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            metrics.objectCount += 1
        }
        return metrics
    }

    private static func cacheObjectCount(
        at accountURL: URL,
        fileManager: FileManager = .default
    ) -> Int {
        folderSnapshotObjectCount(
            at: accountURL.appendingPathComponent("folders.json", isDirectory: false),
            fileManager: fileManager
        )
            + headerSnapshotObjectCount(
                at: accountURL.appendingPathComponent("headers", isDirectory: true),
                fileManager: fileManager
            )
            + rootMessageSourceObjectCount(at: accountURL, fileManager: fileManager)
    }

    private static func folderSnapshotObjectCount(
        at url: URL,
        fileManager: FileManager
    ) -> Int {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(IMAPFolderCacheSnapshot.self, from: data)
        else {
            return 1
        }
        return snapshot.folders.count
    }

    private static func headerSnapshotObjectCount(
        at headersURL: URL,
        fileManager: FileManager
    ) -> Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: headersURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }
        return urls.reduce(into: 0) { count, url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return
            }
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(IMAPMailboxHeaderCacheSnapshot.self, from: data)
            else {
                count += 1
                return
            }
            count += snapshot.headers.count
        }
    }

    private static func rootMessageSourceObjectCount(
        at accountURL: URL,
        fileManager: FileManager
    ) -> Int {
        let headersURL = accountURL.appendingPathComponent("headers", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent != "folders.json",
                  !isDescendant(url, of: headersURL),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                continue
            }
            count += 1
        }
        return count
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    /// Human-readable byte count, e.g. "12.4 MB".
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formattedObjectCount(_ count: Int) -> String {
        count == 1 ? "1 object" : "\(count) objects"
    }

    /// A path suitable for display, abbreviating the home directory with `~`
    /// and hiding the account-specific cache key. Delegates to the shared
    /// `MailCacheKeyNaming` so redaction stays consistent with the Settings panel.
    static func displayPath(for url: URL) -> String {
        MailCacheKeyNaming.displayPath(for: url)
    }
}
