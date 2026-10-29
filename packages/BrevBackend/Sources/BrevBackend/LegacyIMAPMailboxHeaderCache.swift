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

/// Reads pre-ADR-0087 header files for migration; never writes new snapshots.
public actor LegacyIMAPMailboxHeaderCache: IMAPMailboxHeaderCache {
    private let rootDirectory: URL

    /// Uses the historical account cache root unless a synthetic fixture root is supplied.
    public init(rootDirectory: URL? = nil) {
        let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Brev/Cache", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Brev/Cache", isDirectory: true)
        self.rootDirectory = rootDirectory ?? defaultRoot
    }

    /// Decodes a legacy file only when explicitly requested by the migration adapter.
    public func snapshot(accountID: BrevAccount.ID, folderID: Folder.ID) -> IMAPMailboxHeaderCacheSnapshot? {
        let url = directory(accountID).appendingPathComponent("\(MailCacheKeyNaming.hexKey(folderID)).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IMAPMailboxHeaderCacheSnapshot.self, from: data)
    }

    /// Legacy persistence is retired; all new header writes belong in the index or memory.
    public func setSnapshot(_: IMAPMailboxHeaderCacheSnapshot, accountID _: BrevAccount.ID, folderID _: Folder.ID) {}

    /// Removes only a successfully migrated folder's legacy source.
    public func clear(accountID: BrevAccount.ID, folderID: Folder.ID) {
        try? FileManager.default.removeItem(at: directory(accountID).appendingPathComponent("\(MailCacheKeyNaming.hexKey(folderID)).json"))
    }

    /// Removes unvisited legacy header files as part of explicit account-cache cleanup.
    public func clear(accountID: BrevAccount.ID) {
        try? FileManager.default.removeItem(at: directory(accountID))
    }

    private func directory(_ accountID: BrevAccount.ID) -> URL {
        rootDirectory.appendingPathComponent(MailCacheKeyNaming.hexKey(accountID), isDirectory: true)
            .appendingPathComponent("headers", isDirectory: true)
    }
}
