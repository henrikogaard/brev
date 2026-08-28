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

public struct IMAPFolderCacheSnapshot: Codable, Hashable, Sendable {
    public var folders: [Folder]
    public var folderDelimitersByID: [Folder.ID: String]
    /// Whether the account's IMAP server advertised `X-GM-EXT-1` (Gmail
    /// labels) the last time a listing ran. Persisted alongside the folder
    /// snapshot so `.labels` is advertised again on cache-first startup
    /// before the first live listing completes.
    public var supportsGmailLabels: Bool

    public init(
        folders: [Folder],
        folderDelimitersByID: [Folder.ID: String] = [:],
        supportsGmailLabels: Bool = false
    ) {
        self.folders = folders
        self.folderDelimitersByID = folderDelimitersByID
        self.supportsGmailLabels = supportsGmailLabels
    }

    enum CodingKeys: String, CodingKey {
        case folders
        case folderDelimitersByID
        case supportsGmailLabels
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folders = try container.decode([Folder].self, forKey: .folders)
        folderDelimitersByID = try container.decodeIfPresent(
            [Folder.ID: String].self,
            forKey: .folderDelimitersByID
        ) ?? [:]
        supportsGmailLabels = try container.decodeIfPresent(Bool.self, forKey: .supportsGmailLabels) ?? false
    }
}

public protocol IMAPFolderSnapshotCache: Sendable {
    func snapshot(accountID: BrevAccount.ID) async -> IMAPFolderCacheSnapshot?
    func setSnapshot(_ snapshot: IMAPFolderCacheSnapshot, accountID: BrevAccount.ID) async
    func clear(accountID: BrevAccount.ID) async
}

public actor InMemoryIMAPFolderSnapshotCache: IMAPFolderSnapshotCache {
    private var snapshotsByAccount: [BrevAccount.ID: IMAPFolderCacheSnapshot]

    public init(snapshotsByAccount: [BrevAccount.ID: IMAPFolderCacheSnapshot] = [:]) {
        self.snapshotsByAccount = snapshotsByAccount
    }

    public func snapshot(accountID: BrevAccount.ID) -> IMAPFolderCacheSnapshot? {
        snapshotsByAccount[accountID]
    }

    public func setSnapshot(_ snapshot: IMAPFolderCacheSnapshot, accountID: BrevAccount.ID) {
        snapshotsByAccount[accountID] = snapshot
    }

    public func clear(accountID: BrevAccount.ID) {
        snapshotsByAccount.removeValue(forKey: accountID)
    }
}
