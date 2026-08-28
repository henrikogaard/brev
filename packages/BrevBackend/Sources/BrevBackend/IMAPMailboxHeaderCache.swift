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

public struct IMAPMailboxHeaderCacheSnapshot: Codable, Hashable, Sendable {
    public var headers: [MessageHeader]
    public var uidValidity: Int?
    /// CONDSTORE (RFC 4551) mod-sequence watermark. Nil until the first
    /// CONDSTORE-capable SELECT response is received. Used to skip full
    /// re-fetches when the mailbox is unchanged between background refreshes.
    public var highestModSeq: UInt64?
    public var nextPageToken: String?
    public var firstPageHeaderIDs: Set<MessageHeader.ID>?
    public var pageHeaderIDsByToken: [String: Set<MessageHeader.ID>]

    public init(
        headers: [MessageHeader],
        uidValidity: Int? = nil,
        highestModSeq: UInt64? = nil,
        nextPageToken: String? = nil,
        firstPageHeaderIDs: Set<MessageHeader.ID>? = nil,
        pageHeaderIDsByToken: [String: Set<MessageHeader.ID>] = [:]
    ) {
        self.headers = headers
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.nextPageToken = nextPageToken
        self.firstPageHeaderIDs = firstPageHeaderIDs
        self.pageHeaderIDsByToken = pageHeaderIDsByToken
    }
}

public protocol IMAPMailboxHeaderCache: Sendable {
    func snapshot(accountID: BrevAccount.ID, folderID: Folder.ID) async -> IMAPMailboxHeaderCacheSnapshot?
    func setSnapshot(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) async
    func clear(accountID: BrevAccount.ID, folderID: Folder.ID) async
    func clear(accountID: BrevAccount.ID) async
}

public extension IMAPMailboxHeaderCache {
    func headers(accountID: BrevAccount.ID, folderID: Folder.ID) async -> [MessageHeader]? {
        await snapshot(accountID: accountID, folderID: folderID)?.headers
    }

    func setHeaders(
        _ headers: [MessageHeader],
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) async {
        await setSnapshot(
            IMAPMailboxHeaderCacheSnapshot(headers: headers),
            accountID: accountID,
            folderID: folderID
        )
    }
}

public actor InMemoryIMAPMailboxHeaderCache: IMAPMailboxHeaderCache {
    private var snapshotsByFolderByAccount: [BrevAccount.ID: [Folder.ID: IMAPMailboxHeaderCacheSnapshot]]

    public init(
        headersByFolderByAccount: [BrevAccount.ID: [Folder.ID: [MessageHeader]]] = [:],
        snapshotsByFolderByAccount: [BrevAccount.ID: [Folder.ID: IMAPMailboxHeaderCacheSnapshot]] = [:]
    ) {
        self.snapshotsByFolderByAccount = snapshotsByFolderByAccount
        for (accountID, folders) in headersByFolderByAccount {
            var snapshots = self.snapshotsByFolderByAccount[accountID] ?? [:]
            for (folderID, headers) in folders {
                snapshots[folderID] = IMAPMailboxHeaderCacheSnapshot(headers: headers)
            }
            self.snapshotsByFolderByAccount[accountID] = snapshots
        }
    }

    public func snapshot(
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) -> IMAPMailboxHeaderCacheSnapshot? {
        snapshotsByFolderByAccount[accountID]?[folderID]
    }

    public func setSnapshot(
        _ snapshot: IMAPMailboxHeaderCacheSnapshot,
        accountID: BrevAccount.ID,
        folderID: Folder.ID
    ) {
        var folders = snapshotsByFolderByAccount[accountID] ?? [:]
        folders[folderID] = snapshot
        snapshotsByFolderByAccount[accountID] = folders
    }

    public func clear(accountID: BrevAccount.ID, folderID: Folder.ID) {
        snapshotsByFolderByAccount[accountID]?.removeValue(forKey: folderID)
        if snapshotsByFolderByAccount[accountID]?.isEmpty == true {
            snapshotsByFolderByAccount.removeValue(forKey: accountID)
        }
    }

    public func clear(accountID: BrevAccount.ID) {
        snapshotsByFolderByAccount.removeValue(forKey: accountID)
    }
}
