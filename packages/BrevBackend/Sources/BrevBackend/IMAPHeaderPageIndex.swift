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

/// One server page and the metadata that must commit with its header rows.
public struct IMAPHeaderPageWrite: Sendable {
    public let folderID: Folder.ID
    public let pageToken: String?
    public let headers: [MessageHeader]
    public let uidValidity: Int?
    public let highestModSeq: UInt64?
    public let nextPageToken: String?

    /// Creates a first-page write when `pageToken` is nil, or an older-window replacement otherwise.
    public init(folderID: Folder.ID, pageToken: String?, headers: [MessageHeader], uidValidity: Int?,
                highestModSeq: UInt64?, nextPageToken: String?) {
        self.folderID = folderID
        self.pageToken = pageToken
        self.headers = headers
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.nextPageToken = nextPageToken
    }
}

/// Optional index capability for atomic IMAP page/header persistence, without SQL in the backend.
public protocol IMAPHeaderPageIndex: MailLocalSearchIndex {
    /// Commits a page or throws; a failed write must not report durable paging state.
    func storeIMAPPage(_ page: IMAPHeaderPageWrite, account: BrevAccount) async throws
    /// Reads only the folder generation and paging cursor, never its header array.
    func imapHeaderMetadata(folderID: Folder.ID, account: BrevAccount) async throws -> IMAPHeaderMetadata?
    /// Reads only explicitly requested headers from one folder.
    func imapHeaders(ids: [MessageHeader.ID], folderID: Folder.ID, account: BrevAccount) async throws -> [MessageHeader]
    /// Compatibility read for consumers being replaced by selective queries in the next slice.
    func imapHeaderSnapshot(folderID: Folder.ID, account: BrevAccount) async throws -> IMAPMailboxHeaderCacheSnapshot?
    /// Writes a compatibility snapshot or imports missing legacy rows atomically.
    func storeIMAPSnapshot(_ snapshot: IMAPMailboxHeaderCacheSnapshot, folderID: Folder.ID,
                          account: BrevAccount, importingLegacy: Bool) async throws
}

/// Small metadata projection for a cached IMAP folder.
public struct IMAPHeaderMetadata: Sendable {
    public let uidValidity: Int?
    public let highestModSeq: UInt64?
    public let nextPageToken: String?

    /// Creates metadata without loading message headers or page memberships.
    public init(uidValidity: Int?, highestModSeq: UInt64?, nextPageToken: String?) {
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.nextPageToken = nextPageToken
    }
}
